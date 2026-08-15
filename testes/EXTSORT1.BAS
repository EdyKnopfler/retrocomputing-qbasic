' EXTSORT1.BAS
' Prototipo: external merge sort generico (passo 3 do roteiro, ver
' docs/plano-de-trabalho.md). So o mecanismo de ordenacao (gerar runs +
' merge k-vias) - sem agregacao (passo 4, separado) e sem plugar ainda
' no dump de reindexacao ou em vendas reais. Ver docs/decisoes.md
' (2026-08-15) para o desenho.
'
' Decisoes de desenho (confirmadas com o usuario antes do prototipo):
' - Runs num UNICO arquivo (RUNS1.DAT), cada run e uma faixa continua de
'   RRNs - mesma tecnica de faixa+seek do REINDEX1.BAS. Evita abrir 1
'   handle de arquivo por run (risco de estourar FILES= do DOS).
' - Shell sort pra ordenar cada buffer em RAM antes de virar run -
'   in-place, sem recursao, sem patologia de pior caso em entrada ja
'   ordenada/revertida (ao contrario de quicksort ingenuo) - relevante
'   porque esses dois casos estao no roteiro de teste abaixo.
'
' Tecnica de bloco (1 seek + rajada sequencial): GET/PUT com numero de
' registro omitido continua da posicao do GET/PUT anterior, sem seek -
' confirmado no manual, ja usado no REINDEX1.BAS:
' https://www.qbasic.net/en/reference/qb11/Statement/GET-001.htm

TYPE NoRegistro                    ' 11+20 = 31 bytes/registro
  chave AS STRING * 11
  dado  AS STRING * 20
END TYPE

DECLARE SUB GeraEntrada (modo AS INTEGER, n AS LONG)
DECLARE SUB GeraRuns (n AS LONG)
DECLARE SUB OrdenaBuffer (qtd AS INTEGER)
DECLARE SUB EscreveRun (rrnBase AS LONG, qtd AS INTEGER)
DECLARE SUB RefillJanela (k AS INTEGER)
DECLARE SUB AtualizaCabeca (k AS INTEGER)
DECLARE SUB MergeRuns (n AS LONG)
DECLARE SUB EscreveSaida (reg AS NoRegistro)
DECLARE SUB FlushSaidaMerge ()
DECLARE SUB VerificaContagem (n AS LONG)
DECLARE SUB VerificaOrdenado (n AS LONG)
DECLARE SUB VerificaRunsIndividuais ()
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)

CONST BUFRUN% = 90                 ' buffer de sort/run - de proposito nao-divisor de 1000
CONST BUFJANELA% = 20               ' janela de leitura por run, no merge - pequena de proposito
CONST BUFSAI% = 100                 ' buffer de saida do merge
CONST maxRuns% = 20                 ' folga sobre CEIL(1000/90)=12

DIM SHARED noReg AS NoRegistro
DIM SHARED bufOrdena(1 TO BUFRUN%) AS NoRegistro

' --- runs (faixas dentro de RUNS1.DAT) ---
DIM SHARED runInicio(1 TO maxRuns%) AS LONG, runFim(1 TO maxRuns%) AS LONG
DIM SHARED numRuns AS INTEGER

' --- estado do merge k-vias ---
DIM SHARED runProximo(1 TO maxRuns%) AS LONG
DIM SHARED runBufLo(1 TO maxRuns%) AS LONG, runBufHi(1 TO maxRuns%) AS LONG
DIM SHARED runAtivo(1 TO maxRuns%) AS INTEGER
DIM SHARED janela(1 TO maxRuns%, 1 TO BUFJANELA%) AS NoRegistro
DIM SHARED headChave(1 TO maxRuns%) AS STRING * 11
DIM SHARED headDado(1 TO maxRuns%) AS STRING * 20
DIM SHARED proxRRNSaidaMerge AS LONG

' --- buffer de saida do merge ---
DIM SHARED outBufM(1 TO BUFSAI%) AS NoRegistro
DIM SHARED outBufMCount AS INTEGER, outBufMBaseRRN AS LONG

' --- contadores de I/O (zerados por cenario) ---
DIM SHARED contSeeksGeracaoEntrada AS LONG
DIM SHARED contSeeksGeracaoSaida AS LONG, contGravacoesGeracaoSaida AS LONG
DIM SHARED contSeeksMergeEntrada AS LONG, contLeiturasMergeEntrada AS LONG
DIM SHARED contSeeksMergeSaida AS LONG, contGravacoesMergeSaida AS LONG
DIM SHARED contSeeksPorRun(1 TO maxRuns%) AS LONG

DIM SHARED totalFalhas AS INTEGER

DIM cenarioModo AS INTEGER, cenarioN AS LONG, cenarioDesc AS STRING
DIM esperadoRuns AS LONG, tamRun AS LONG, tetoSeeks AS LONG, zk AS INTEGER

' ---------------------------------------------------------------------
' Harness
' ---------------------------------------------------------------------

OPEN "EXTSORT1.LOG" FOR OUTPUT AS #4
PRINT #4, "=== EXTSORT1.BAS - external merge sort, BUFRUN="; BUFRUN%; " BUFJANELA="; BUFJANELA%; " BUFSAI="; BUFSAI%; " ==="

ON ERROR GOTO TrataErro

cenarioModo = 0: cenarioN = 1000: cenarioDesc = "Principal (embaralhado + duplicatas)"
GOSUB ExecutaCenario

cenarioModo = 1: cenarioN = 50: cenarioDesc = "Ja ordenado (melhor caso do sort)"
GOSUB ExecutaCenario

cenarioModo = 2: cenarioN = 50: cenarioDesc = "Ordem reversa (pior caso do sort)"
GOSUB ExecutaCenario

cenarioModo = 3: cenarioN = 10: cenarioDesc = "N menor que 1 buffer de run (run unica)"
GOSUB ExecutaCenario

PRINT #4, ""
PRINT #4, "=== FIM. Falhas: "; totalFalhas; " ==="
CLOSE #1, #2, #3, #4

PRINT
PRINT "EXTSORT1 OK. Falhas: "; totalFalhas; ". Ver EXTSORT1.LOG"
SYSTEM

TrataErro:
PRINT #4, "*** ERRO EM RUNTIME (EXTSORT1) *** ERR="; ERR; " ERL="; ERL
CLOSE #4
SYSTEM

' -----------------------------------------------------------------
' GOSUB (nao SUB - precisa de ON ERROR GOTO pro KILL condicional, so
' vale no programa principal): roda 1 cenario completo (gera entrada,
' ordena em runs, faz merge, verifica, mede I/O)
' -----------------------------------------------------------------
ExecutaCenario:
  PRINT #4, ""
  PRINT #4, "--- Cenario: "; cenarioDesc; " (modo="; cenarioModo; " N="; cenarioN; ") ---"

  ON ERROR GOTO SemEnt
  KILL "ENTRADA1.DAT"
  GOTO ApagouEnt
  SemEnt:
  RESUME ApagouEnt
  ApagouEnt:
  ON ERROR GOTO TrataErro

  ON ERROR GOTO SemRuns
  KILL "RUNS1.DAT"
  GOTO ApagouRuns
  SemRuns:
  RESUME ApagouRuns
  ApagouRuns:
  ON ERROR GOTO TrataErro

  ON ERROR GOTO SemSaida
  KILL "SAIDA1.DAT"
  GOTO ApagouSaida
  SemSaida:
  RESUME ApagouSaida
  ApagouSaida:
  ON ERROR GOTO TrataErro

  OPEN "ENTRADA1.DAT" FOR RANDOM AS #1 LEN = LEN(noReg)
  OPEN "RUNS1.DAT" FOR RANDOM AS #2 LEN = LEN(noReg)
  OPEN "SAIDA1.DAT" FOR RANDOM AS #3 LEN = LEN(noReg)

  contSeeksGeracaoEntrada = 0
  contSeeksGeracaoSaida = 0: contGravacoesGeracaoSaida = 0
  contSeeksMergeEntrada = 0: contLeiturasMergeEntrada = 0
  contSeeksMergeSaida = 0: contGravacoesMergeSaida = 0
  FOR zk = 1 TO maxRuns%
    contSeeksPorRun(zk) = 0
  NEXT zk

  CALL GeraEntrada(cenarioModo, cenarioN)
  CALL GeraRuns(cenarioN)

  esperadoRuns = (cenarioN + BUFRUN% - 1) \ BUFRUN%
  CALL Confere("numero de runs = CEIL(N/BUFRUN)", LTRIM$(STR$(esperadoRuns)), LTRIM$(STR$(numRuns)))

  CALL VerificaRunsIndividuais

  CALL MergeRuns(cenarioN)

  CALL VerificaContagem(cenarioN)
  CALL VerificaOrdenado(cenarioN)

  PRINT #4, "I/O geracao de runs: seeks entrada="; contSeeksGeracaoEntrada; " seeks saida="; contSeeksGeracaoSaida; " gravacoes saida="; contGravacoesGeracaoSaida
  PRINT #4, "I/O merge: seeks entrada="; contSeeksMergeEntrada; " leituras="; contLeiturasMergeEntrada; " seeks saida="; contSeeksMergeSaida; " gravacoes saida="; contGravacoesMergeSaida

  FOR zk = 1 TO numRuns
    tamRun = runFim(zk) - runInicio(zk) + 1
    tetoSeeks = (tamRun + BUFJANELA% - 1) \ BUFJANELA%
    CALL Confere("run " + LTRIM$(STR$(zk)) + ": seeks merge <= teto N/janela (" + LTRIM$(STR$(tetoSeeks)) + ")", "-1", LTRIM$(STR$(contSeeksPorRun(zk) <= tetoSeeks)))
  NEXT zk

  CLOSE #1, #2, #3
  PRINT ".";
RETURN

' ---------------------------------------------------------------------
' Gera ENTRADA1.DAT com n registros, no modo pedido:
'   0 = embaralhado (permutacao multiplicativa) + duplicatas forcadas
'   1 = ja ordenado (chave = i)
'   2 = ordem reversa (chave = n-i+1)
'   3 = embaralhado, sem duplicatas forcadas (cenario pequeno)
' ---------------------------------------------------------------------
SUB GeraEntrada (modo AS INTEGER, n AS LONG)
  DIM i AS LONG, valor AS LONG, ultimoValor AS LONG

  FOR i = 1 TO n
    SELECT CASE modo
      CASE 1
        valor = i
      CASE 2
        valor = n - i + 1
      CASE ELSE
        valor = ((i - 1) * 37) MOD n
        IF modo = 0 AND i > 1 AND (i MOD 5 = 0) THEN valor = ultimoValor
    END SELECT
    ultimoValor = valor

    noReg.chave = RIGHT$("00000000000" + LTRIM$(STR$(valor)), 11)
    noReg.dado = "REG" + LTRIM$(STR$(i))

    IF i = 1 THEN
      PUT #1, 1, noReg
    ELSE
      PUT #1, , noReg
    END IF
  NEXT i
END SUB

' ---------------------------------------------------------------------
' Fase 1: le a entrada em blocos de BUFRUN, ordena cada bloco em RAM
' (shell sort) e grava como uma run continua em RUNS1.DAT. Leitura da
' entrada e escrita das runs sao cada uma inteiramente sequenciais (sem
' lacuna entre blocos/runs) - so 1 seek em cada lado, o resto e rajada.
' ---------------------------------------------------------------------
SUB GeraRuns (n AS LONG)
  DIM posAtual AS LONG, restante AS LONG, tamanho AS INTEGER, k AS INTEGER

  numRuns = 0
  posAtual = 1
  DO WHILE posAtual <= n
    restante = n - posAtual + 1
    IF restante > BUFRUN% THEN
      tamanho = BUFRUN%
    ELSE
      tamanho = restante
    END IF

    IF posAtual = 1 THEN
      GET #1, 1, bufOrdena(1)
      contSeeksGeracaoEntrada = contSeeksGeracaoEntrada + 1
    ELSE
      GET #1, , bufOrdena(1)
    END IF
    FOR k = 2 TO tamanho
      GET #1, , bufOrdena(k)
    NEXT k

    CALL OrdenaBuffer(tamanho)

    numRuns = numRuns + 1
    runInicio(numRuns) = posAtual
    runFim(numRuns) = posAtual + tamanho - 1
    CALL EscreveRun(posAtual, tamanho)

    posAtual = posAtual + tamanho
  LOOP
  PRINT ".";
END SUB

' ---------------------------------------------------------------------
' Shell sort classico (gaps decrescentes, /2), in-place, sem recursao -
' opera sobre bufOrdena(1..qtd). Ver cabecalho do arquivo pro motivo da
' escolha (sem array auxiliar, sem pior caso em entrada ja
' ordenada/revertida - ao contrario de quicksort ingenuo).
' ---------------------------------------------------------------------
SUB OrdenaBuffer (qtd AS INTEGER)
  DIM gap AS INTEGER, i AS INTEGER, j AS INTEGER
  DIM temp AS NoRegistro

  gap = qtd \ 2
  DO WHILE gap > 0
    FOR i = gap + 1 TO qtd
      temp = bufOrdena(i)
      j = i
      DO WHILE j > gap
        IF bufOrdena(j - gap).chave <= temp.chave THEN EXIT DO
        bufOrdena(j) = bufOrdena(j - gap)
        j = j - gap
      LOOP
      bufOrdena(j) = temp
    NEXT i
    gap = gap \ 2
  LOOP
END SUB

' ---------------------------------------------------------------------
' Grava bufOrdena(1..qtd) como run continua em RUNS1.DAT, comecando em
' rrnBase. Runs sao gravadas em sequencia sem lacuna (rrnBase da run
' seguinte = runFim+1 da anterior), entao so a primeira PUT do arquivo
' inteiro precisa de posicao explicita - o resto encadeia sequencial.
' ---------------------------------------------------------------------
SUB EscreveRun (rrnBase AS LONG, qtd AS INTEGER)
  DIM k AS INTEGER

  IF rrnBase = 1 THEN
    PUT #2, 1, bufOrdena(1)
    contSeeksGeracaoSaida = contSeeksGeracaoSaida + 1
  ELSE
    PUT #2, , bufOrdena(1)
  END IF
  FOR k = 2 TO qtd
    PUT #2, , bufOrdena(k)
  NEXT k
  contGravacoesGeracaoSaida = contGravacoesGeracaoSaida + qtd
END SUB

' ---------------------------------------------------------------------
' Recarrega a janela de leitura da run k a partir de runProximo(k) - 1
' seek posicionado + rajada sequencial ate encher a janela ou a run
' acabar. Sempre posicionado (nunca omite numero), mesmo quando por
' acaso continuaria sequencial de um refill anterior da mesma run -
' mesma convencao conservadora do LeDump do REINDEX1.BAS.
' ---------------------------------------------------------------------
SUB RefillJanela (k AS INTEGER)
  DIM posIni AS LONG, novoHi AS LONG, j AS INTEGER

  IF runProximo(k) > runFim(k) THEN
    runAtivo(k) = 0
    EXIT SUB
  END IF

  posIni = runProximo(k)
  novoHi = posIni + BUFJANELA% - 1
  IF novoHi > runFim(k) THEN novoHi = runFim(k)

  GET #2, posIni, janela(k, 1)
  FOR j = 2 TO (novoHi - posIni + 1)
    GET #2, , janela(k, j)
  NEXT j

  runBufLo(k) = posIni
  runBufHi(k) = novoHi
  contSeeksMergeEntrada = contSeeksMergeEntrada + 1
  contSeeksPorRun(k) = contSeeksPorRun(k) + 1
  contLeiturasMergeEntrada = contLeiturasMergeEntrada + (novoHi - posIni + 1)
END SUB

' ---------------------------------------------------------------------
' Garante que headChave(k)/headDado(k) reflitam o registro em
' runProximo(k) - refaz a janela se necessario, ou desativa a run se
' ja esgotou.
' ---------------------------------------------------------------------
SUB AtualizaCabeca (k AS INTEGER)
  DIM idx AS INTEGER

  IF runProximo(k) > runFim(k) THEN
    runAtivo(k) = 0
    EXIT SUB
  END IF

  IF runProximo(k) < runBufLo(k) OR runProximo(k) > runBufHi(k) THEN
    CALL RefillJanela(k)
    IF runAtivo(k) = 0 THEN EXIT SUB
  END IF

  idx = runProximo(k) - runBufLo(k) + 1
  headChave(k) = janela(k, idx).chave
  headDado(k) = janela(k, idx).dado
END SUB

' ---------------------------------------------------------------------
' Fase 2: merge k-vias. Cada passo varre as cabecas das runs ativas
' (varredura linear - k e pequeno, nao compensa heap), escreve a menor
' na saida, avanca so aquela run.
' ---------------------------------------------------------------------
SUB MergeRuns (n AS LONG)
  DIM k AS INTEGER, melhorRun AS INTEGER, achou AS INTEGER
  DIM melhorChave AS STRING
  DIM regSaida AS NoRegistro

  FOR k = 1 TO numRuns
    runProximo(k) = runInicio(k)
    runBufLo(k) = 1
    runBufHi(k) = 0                ' janela vazia, forca refill na 1a AtualizaCabeca
    runAtivo(k) = -1
    CALL AtualizaCabeca(k)
  NEXT k

  outBufMCount = 0
  proxRRNSaidaMerge = 1

  DO
    achou = 0
    FOR k = 1 TO numRuns
      IF runAtivo(k) THEN
        IF achou = 0 THEN
          melhorChave = headChave(k)
          melhorRun = k
          achou = -1
        ELSEIF headChave(k) < melhorChave THEN
          melhorChave = headChave(k)
          melhorRun = k
        END IF
      END IF
    NEXT k
    IF achou = 0 THEN EXIT DO

    regSaida.chave = headChave(melhorRun)
    regSaida.dado = headDado(melhorRun)
    CALL EscreveSaida(regSaida)

    runProximo(melhorRun) = runProximo(melhorRun) + 1
    CALL AtualizaCabeca(melhorRun)
  LOOP

  CALL FlushSaidaMerge
END SUB

' ---------------------------------------------------------------------
' Acumula um registro no buffer de saida do merge; flush automatico
' quando enche.
' ---------------------------------------------------------------------
SUB EscreveSaida (reg AS NoRegistro)
  IF outBufMCount = 0 THEN outBufMBaseRRN = proxRRNSaidaMerge
  outBufMCount = outBufMCount + 1
  outBufM(outBufMCount) = reg
  proxRRNSaidaMerge = proxRRNSaidaMerge + 1
  IF outBufMCount = BUFSAI% THEN CALL FlushSaidaMerge
END SUB

' ---------------------------------------------------------------------
' Despeja o buffer de saida do merge: 1 PUT posicionado + rajada
' sequencial, igual ao FlushSaida do REINDEX1.BAS.
' ---------------------------------------------------------------------
SUB FlushSaidaMerge
  DIM k AS INTEGER
  IF outBufMCount = 0 THEN EXIT SUB

  PUT #3, outBufMBaseRRN, outBufM(1)
  FOR k = 2 TO outBufMCount
    PUT #3, , outBufM(k)
  NEXT k
  contSeeksMergeSaida = contSeeksMergeSaida + 1
  contGravacoesMergeSaida = contGravacoesMergeSaida + outBufMCount

  outBufMCount = 0
  PRINT ".";
END SUB

' ---------------------------------------------------------------------
' Verificacoes
' ---------------------------------------------------------------------
SUB VerificaContagem (n AS LONG)
  DIM totalSaida AS LONG
  totalSaida = LOF(3) \ LEN(noReg)
  CALL Confere("contagem: registros na saida = registros na entrada", LTRIM$(STR$(n)), LTRIM$(STR$(totalSaida)))
END SUB

SUB VerificaOrdenado (n AS LONG)
  DIM i AS LONG, falhas AS LONG
  DIM anterior AS NoRegistro, atual AS NoRegistro

  falhas = 0
  GET #3, 1, anterior
  FOR i = 2 TO n
    GET #3, , atual
    IF atual.chave < anterior.chave THEN falhas = falhas + 1
    anterior = atual
  NEXT i
  CALL Confere("saida totalmente ordenada (comparacao adjacente completa)", "0", LTRIM$(STR$(falhas)))
END SUB

SUB VerificaRunsIndividuais
  DIM k AS INTEGER, i AS LONG, falhas AS LONG
  DIM anterior AS NoRegistro, atual AS NoRegistro

  falhas = 0
  FOR k = 1 TO numRuns
    GET #2, runInicio(k), anterior
    FOR i = runInicio(k) + 1 TO runFim(k)
      GET #2, , atual
      IF atual.chave < anterior.chave THEN falhas = falhas + 1
      anterior = atual
    NEXT i
  NEXT k
  CALL Confere("cada run individualmente ordenada antes do merge", "0", LTRIM$(STR$(falhas)))
END SUB

' ---------------------------------------------------------------------
' Assert simples: grava OK/FALHA no log e conta falhas
' ---------------------------------------------------------------------
SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
  IF esperado = obtido THEN
    PRINT #4, "OK    - "; descricao
  ELSE
    PRINT #4, "FALHA - "; descricao; " | esperado=["; esperado; "] obtido=["; obtido; "]"
    totalFalhas = totalFalhas + 1
  END IF
END SUB
