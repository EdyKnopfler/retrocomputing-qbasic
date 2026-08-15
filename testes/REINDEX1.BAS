' REINDEX1.BAS
' Prototipo: reconstrucao da arvore balanceada por bissecao a partir de
' um dump ja ordenado (numeracao de RRN em largura/BFS, fila explicita,
' buffers de entrada/saida pequenos "de proposito no teste" - mesmo
' truque do ARVDISCO.BAS/CADCLI3.BAS). Ver docs/reindexacao.md e
' docs/decisoes.md (2026-08-15) para o desenho.
'
' Escopo: SO a reconstrucao (passo 2 do processo em docs/reindexacao.md).
' O dump e gerado direto ja ordenado (chave = contagem sequencial), sem
' rodar external merge sort de verdade - isso e passo 3 do roteiro em
' docs/plano-de-trabalho.md, ainda nao prototipado, prototipo separado.
'
' Tecnica de bloco (1 seek + rajada sequencial): GET/PUT com numero de
' registro omitido continua da posicao do GET/PUT anterior, sem seek -
' confirmado no manual (nao e idiomatismo de VB vazando, e sintaxe real
' do QBasic): https://www.qbasic.net/en/reference/qb11/Statement/GET-001.htm

TYPE NoDump                        ' 11+30 = 41 bytes/registro
  chave AS STRING * 11
  nome  AS STRING * 30
END TYPE

TYPE NoArvore                      ' 11+30+4+4+2 = 51 bytes/registro
  chave    AS STRING * 11
  nome     AS STRING * 30
  esquerda AS LONG
  direita  AS LONG
  excluido AS INTEGER
END TYPE

DECLARE SUB GeraDump ()
DECLARE SUB LeDump (posDump AS LONG, chave AS STRING, nome AS STRING)
DECLARE SUB Enfileira (lo AS LONG, hi AS LONG, rrnDestino AS LONG)
DECLARE SUB EscreveArvore (rrn AS LONG, reg AS NoArvore)
DECLARE SUB FlushSaida ()
DECLARE SUB VerificaEmOrdem (rrn AS LONG, profundidade AS INTEGER)
DECLARE SUB VerificaLargura ()
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)

CONST totalRegistros& = 1000              ' registros no dump (producao: milhares)
CONST BUFENT% = 100                ' buffer de entrada, pequeno de proposito
CONST BUFSAI% = 100                ' buffer de saida, pequeno de proposito

DIM SHARED noDump AS NoDump
DIM SHARED noArv AS NoArvore

' --- fila de faixas pendentes (lo, hi no dump; RRN de destino na saida) ---
DIM SHARED filaLo(1 TO totalRegistros&) AS LONG
DIM SHARED filaHi(1 TO totalRegistros&) AS LONG
DIM SHARED filaRRN(1 TO totalRegistros&) AS LONG
DIM SHARED filaIni AS LONG, filaFim AS LONG

' --- buffer de entrada (dump) ---
DIM SHARED inBuf(1 TO BUFENT%) AS NoDump
DIM SHARED inBufLo AS LONG, inBufHi AS LONG
DIM SHARED contSeeksEntrada AS LONG, contLeiturasEntrada AS LONG
DIM SHARED contAcertosBufferEntrada AS LONG

' --- buffer de saida (arvore) ---
DIM SHARED outBuf(1 TO BUFSAI%) AS NoArvore
DIM SHARED outBufCount AS INTEGER, outBufBaseRRN AS LONG
DIM SHARED contSeeksSaida AS LONG, contGravacoesSaida AS LONG

DIM SHARED totalFalhas AS INTEGER
DIM SHARED contVerificados AS LONG, ordemFalhas AS INTEGER, profMax AS INTEGER

DIM proxRRNSaida AS LONG, lo AS LONG, hi AS LONG, mid AS LONG, rrnDestino AS LONG
DIM rrnEsq AS LONG, rrnDir AS LONG, chaveNo AS STRING, nomeNo AS STRING
DIM falhaLarguraTxt AS STRING

' ---------------------------------------------------------------------
' Harness
' ---------------------------------------------------------------------

ON ERROR GOTO SemDump1
KILL "DUMP1.DAT"
GOTO ApagouDump1
SemDump1:
RESUME ApagouDump1
ApagouDump1:
ON ERROR GOTO 0

ON ERROR GOTO SemArv1
KILL "ARV1.DAT"
GOTO ApagouArv1
SemArv1:
RESUME ApagouArv1
ApagouArv1:
ON ERROR GOTO 0

OPEN "REINDEX1.LOG" FOR OUTPUT AS #3
PRINT #3, "=== REINDEX1.BAS - reconstrucao por bissecao, N="; totalRegistros&; " BUFENT="; BUFENT%; " BUFSAI="; BUFSAI%; " ==="

ON ERROR GOTO TrataErro

OPEN "DUMP1.DAT" FOR RANDOM AS #1 LEN = LEN(noDump)
OPEN "ARV1.DAT" FOR RANDOM AS #2 LEN = LEN(noArv)

PRINT "Gerando dump ordenado..."
CALL GeraDump
PRINT #3, "Dump gerado: "; totalRegistros&; " registros em DUMP1.DAT"

' --- reconstrucao por bissecao, numeracao de RRN em largura (fila FIFO) ---
PRINT "Reconstruindo arvore..."
filaIni = 1: filaFim = 0
proxRRNSaida = 1
CALL Enfileira(1, totalRegistros&, proxRRNSaida)

DO WHILE filaIni <= filaFim
  lo = filaLo(filaIni)
  hi = filaHi(filaIni)
  rrnDestino = filaRRN(filaIni)
  filaIni = filaIni + 1

  mid = (lo + hi) \ 2
  CALL LeDump(mid, chaveNo, nomeNo)

  rrnEsq = 0
  IF mid - 1 >= lo THEN
    proxRRNSaida = proxRRNSaida + 1
    rrnEsq = proxRRNSaida
    CALL Enfileira(lo, mid - 1, rrnEsq)
  END IF

  rrnDir = 0
  IF hi >= mid + 1 THEN
    proxRRNSaida = proxRRNSaida + 1
    rrnDir = proxRRNSaida
    CALL Enfileira(mid + 1, hi, rrnDir)
  END IF

  noArv.chave = chaveNo
  noArv.nome = nomeNo
  noArv.esquerda = rrnEsq
  noArv.direita = rrnDir
  noArv.excluido = 0
  CALL EscreveArvore(rrnDestino, noArv)

  IF rrnDestino MOD 200 = 0 THEN PRINT "."; ' so pra mostrar que esta vivo
LOOP
CALL FlushSaida

PRINT #3, ""
PRINT #3, "=== Reconstrucao concluida ==="
CALL Confere("total de nos gravados = totalRegistros", LTRIM$(STR$(totalRegistros&)), LTRIM$(STR$(proxRRNSaida)))

PRINT #3, ""
PRINT #3, "--- I/O da reconstrucao (o que estamos medindo) ---"
PRINT #3, "Entrada (dump): seeks="; contSeeksEntrada; "  leituras totais (GET)="; contLeiturasEntrada; "  acertos de buffer (sem I/O)="; contAcertosBufferEntrada
PRINT #3, "Saida (arvore): seeks="; contSeeksSaida; "  gravacoes totais (PUT)="; contGravacoesSaida
PRINT #3, "Baseline ingenuo (sem buffer, 1 seek por registro): entrada="; totalRegistros&; " saida="; totalRegistros&

CALL Confere("saida: seeks = totalRegistros/BUFSAI (escrita e sempre sequencial - provado no desenho)", LTRIM$(STR$(totalRegistros& \ BUFSAI%)), LTRIM$(STR$(contSeeksSaida)))
CALL Confere("saida: gravacoes totais = totalRegistros", LTRIM$(STR$(totalRegistros&)), LTRIM$(STR$(contGravacoesSaida)))

' --- verificacao 1: em-ordem via ponteiros reproduz a sequencia ordenada ---
PRINT "Verificando (em-ordem)..."
contVerificados = 0: ordemFalhas = 0: profMax = 0
CALL VerificaEmOrdem(1, 0)
CALL Confere("em-ordem: todos os totalRegistros registros visitados", LTRIM$(STR$(totalRegistros&)), LTRIM$(STR$(contVerificados)))
CALL Confere("em-ordem: 0 falhas de sequencia (bissecao+ponteiros corretos)", "0", LTRIM$(STR$(ordemFalhas)))
PRINT #3, "Profundidade maxima observada: "; profMax
CALL Confere("profundidade maxima <= 10 (teto teorico p/ N=1000, ceil(log2(1000))=10)", "-1", LTRIM$(STR$(profMax <= 10)))

' --- verificacao 2: BFS independente confirma numeracao em largura ---
PRINT "Verificando (largura/BFS)..."
CALL VerificaLargura

PRINT #3, ""
PRINT #3, "=== FIM. Falhas: "; totalFalhas; " ==="
CLOSE #1, #2, #3

PRINT
PRINT "REINDEX1 OK. Falhas: "; totalFalhas; ". Ver REINDEX1.LOG"
SYSTEM

TrataErro:
PRINT #3, "*** ERRO EM RUNTIME (REINDEX1) *** ERR="; ERR; " ERL="; ERL
CLOSE #3
SYSTEM

' ---------------------------------------------------------------------
' Gera DUMP1.DAT: totalRegistros registros ja ordenados por construcao (chave =
' contagem sequencial zero-padded, como um dump pos-external-sort sem
' excluidos). Nome: nome de uma lista limitada + numero, so pra dar
' variedade legivel no log - nao influencia o teste (a ordenacao e pela
' chave).
' ---------------------------------------------------------------------
SUB GeraDump
  DIM listaNomes(1 TO 10) AS STRING * 20
  DIM i AS LONG, n AS INTEGER

  DATA "Maria Luiza","Jose Augusto","Ana Paula","Joao Pedro","Francisca Alves"
  DATA "Carlos Eduardo","Antonia Souza","Paulo Roberto","Sebastiana Lima","Raimundo Nonato"

  FOR n = 1 TO 10
    READ listaNomes(n)
  NEXT n

  FOR i = 1 TO totalRegistros&
    noDump.chave = RIGHT$("00000000000" + LTRIM$(STR$(i)), 11)
    noDump.nome = RTRIM$(listaNomes(((i - 1) MOD 10) + 1)) + " " + LTRIM$(STR$(i))
    PUT #1, i, noDump
  NEXT i
END SUB

' ---------------------------------------------------------------------
' Le um registro do dump pela posicao (indice no dump, 1..totalRegistros). Usa
' buffer de BUFENT% registros: se pos ja esta na janela carregada, serve
' direto (sem I/O nenhum); senao, 1 GET posicionado (seek) + GET's com
' numero de registro omitido (continuam sequencial, sem seek) ate encher
' o buffer ou acabar o dump.
' ---------------------------------------------------------------------
SUB LeDump (posDump AS LONG, chave AS STRING, nome AS STRING)
  DIM k AS LONG, novoHi AS LONG

  IF posDump < inBufLo OR posDump > inBufHi THEN
    GET #1, posDump, inBuf(1)              ' 1 seek: posiciona no meio da faixa
    novoHi = posDump + BUFENT% - 1
    IF novoHi > totalRegistros& THEN novoHi = totalRegistros&
    FOR k = 2 TO (novoHi - posDump + 1)
      GET #1, , inBuf(k)                   ' sequencial, sem seek
    NEXT k
    inBufLo = posDump
    inBufHi = novoHi
    contSeeksEntrada = contSeeksEntrada + 1
    contLeiturasEntrada = contLeiturasEntrada + (novoHi - posDump + 1)
  ELSE
    contAcertosBufferEntrada = contAcertosBufferEntrada + 1
  END IF

  chave = inBuf(posDump - inBufLo + 1).chave
  nome = RTRIM$(inBuf(posDump - inBufLo + 1).nome)
END SUB

' ---------------------------------------------------------------------
' Enfileira uma faixa pendente do dump com o RRN de destino ja atribuido
' (mesmo mecanismo de "proxima posicao livre" da insercao normal) - RRN
' e atribuido na hora de enfileirar, nao existe formula fechada
' equivalente (ver docs/decisoes.md).
' ---------------------------------------------------------------------
SUB Enfileira (lo AS LONG, hi AS LONG, rrnDestino AS LONG)
  filaFim = filaFim + 1
  filaLo(filaFim) = lo
  filaHi(filaFim) = hi
  filaRRN(filaFim) = rrnDestino
END SUB

' ---------------------------------------------------------------------
' Acumula um no no buffer de saida; flush automatico quando enche. Como
' a fila FIFO + atribuicao de RRN em ordem crescente garante que os RRN
' de destino chegam SEMPRE em sequencia estrita 1,2,3... (largura), o
' buffer de saida nunca precisa reordenar nada - so acumula e despeja.
' ---------------------------------------------------------------------
SUB EscreveArvore (rrn AS LONG, reg AS NoArvore)
  IF outBufCount = 0 THEN outBufBaseRRN = rrn
  outBufCount = outBufCount + 1
  outBuf(outBufCount) = reg
  IF outBufCount = BUFSAI% THEN CALL FlushSaida
END SUB

' ---------------------------------------------------------------------
' Despeja o buffer de saida: 1 PUT posicionado (seek) + PUT's com numero
' de registro omitido (sequencial, sem seek) para o resto do bloco.
' ---------------------------------------------------------------------
SUB FlushSaida
  DIM k AS INTEGER
  IF outBufCount = 0 THEN EXIT SUB

  PUT #2, outBufBaseRRN, outBuf(1)         ' 1 seek: posiciona no comeco do bloco
  FOR k = 2 TO outBufCount
    PUT #2, , outBuf(k)                    ' sequencial, sem seek
  NEXT k
  contSeeksSaida = contSeeksSaida + 1
  contGravacoesSaida = contGravacoesSaida + outBufCount

  outBufCount = 0
END SUB

' ---------------------------------------------------------------------
' Percurso em-ordem via ponteiros (arquivo ARV1.DAT, sem cache - nao e o
' que estamos medindo aqui). Confirma: (a) a bissecao+ponteiros reproduz
' a sequencia ordenada original: (b) profundidade maxima da arvore.
' ---------------------------------------------------------------------
SUB VerificaEmOrdem (rrn AS LONG, profundidade AS INTEGER)
  DIM reg AS NoArvore
  DIM chaveEsperada AS STRING

  IF rrn = 0 THEN EXIT SUB
  IF profundidade > profMax THEN profMax = profundidade

  GET #2, rrn, reg
  CALL VerificaEmOrdem(reg.esquerda, profundidade + 1)

  contVerificados = contVerificados + 1
  chaveEsperada = RIGHT$("00000000000" + LTRIM$(STR$(contVerificados)), 11)
  IF reg.chave <> chaveEsperada THEN ordemFalhas = ordemFalhas + 1

  CALL VerificaEmOrdem(reg.direita, profundidade + 1)
END SUB

' ---------------------------------------------------------------------
' Percurso em largura (BFS) independente, via ponteiros do arquivo final
' - confirma que a numeracao de RRN e realmente em largura (visita RRN
' 1,2,3,...,totalRegistros em ordem estrita), sem depender de como foi montada.
' ---------------------------------------------------------------------
SUB VerificaLargura
  DIM filaVer(1 TO totalRegistros&) AS LONG
  DIM verIni AS LONG, verFim AS LONG, rrnAtual AS LONG, esperado AS LONG
  DIM reg AS NoArvore
  DIM falhas AS INTEGER

  verIni = 1: verFim = 1: filaVer(1) = 1
  esperado = 1: falhas = 0

  DO WHILE verIni <= verFim
    rrnAtual = filaVer(verIni)
    verIni = verIni + 1
    IF rrnAtual <> esperado THEN falhas = falhas + 1
    esperado = esperado + 1

    GET #2, rrnAtual, reg
    IF reg.esquerda <> 0 THEN
      verFim = verFim + 1
      filaVer(verFim) = reg.esquerda
    END IF
    IF reg.direita <> 0 THEN
      verFim = verFim + 1
      filaVer(verFim) = reg.direita
    END IF
  LOOP

  CALL Confere("largura/BFS: nos visitados = totalRegistros", LTRIM$(STR$(totalRegistros&)), LTRIM$(STR$(verFim)))
  CALL Confere("largura/BFS: RRN visitado em sequencia estrita 1,2,3...N (numeracao em largura confirmada)", "0", LTRIM$(STR$(falhas)))
END SUB

' ---------------------------------------------------------------------
' Assert simples: grava OK/FALHA no log e conta falhas
' ---------------------------------------------------------------------
SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
  IF esperado = obtido THEN
    PRINT #3, "OK    - "; descricao
  ELSE
    PRINT #3, "FALHA - "; descricao; " | esperado=["; esperado; "] obtido=["; obtido; "]"
    totalFalhas = totalFalhas + 1
  END IF
END SUB
