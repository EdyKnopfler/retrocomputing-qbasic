' CADCLI3.BAS
' Prototipo: mesma logica de indice primario autoindexado por CPF de
' CADCLI1.BAS/CADCLI2.BAS, mas com capacidadeCache% deliberadamente
' minusculo (2 - mesmo truque do ARVDISCO.BAS, que usa 50 "de proposito
' no teste") pra forcar nos ALEM da faixa cacheada e validar o fallback
' pro arquivo (LeNoNav/GravaRegistro/AbreArquivo), que no CADCLI1/2
' nunca foi exercitado (so 3 clientes, cache de 500 - nada nunca saiu
' do array).
'
' Insere 9 clientes em ORDEM CRESCENTE de CPF -> cada um vira filho
' DIREITO do anterior (arvore totalmente enviesada, pior caso de
' profundidade). RRN1/RRN2 ficam no cache; RRN3..RRN9 ficam SO no
' arquivo. Busca por uma chave profunda (RRN9) atravessa 2 nos via
' cache + 7 nos via GET direto do arquivo, num unico Busca.
'
' Descartavel, nao e arquivo de producao. Ver docs/decisoes.md sobre o
' desenho do indice primario (sem registro de cabecalho, raiz = RRN 1).

TYPE NoCliente                    ' 11+50+16+80+80+9+30+2+4+4+2 = 288 bytes/registro
  cpf         AS STRING * 11
  nome        AS STRING * 50
  telefone    AS STRING * 16
  endereco    AS STRING * 80
  complemento AS STRING * 80
  cep         AS STRING * 9
  cidade      AS STRING * 30
  uf          AS STRING * 2
  esquerda    AS LONG
  direita     AS LONG
  excluido    AS INTEGER          ' 0 = ativo, 1 = removido (logico, no fica na arvore)
END TYPE

DECLARE SUB AbreArquivo ()
DECLARE SUB LeNoNav (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
DECLARE SUB CarregaRegistro (rrn AS LONG, reg AS NoCliente)
DECLARE SUB GravaRegistro (rrn AS LONG, reg AS NoCliente)
DECLARE SUB Busca (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB InsereOuReativa (reg AS NoCliente, sucesso AS INTEGER, reativado AS INTEGER)
DECLARE SUB MarcaRemovido (cpfProc AS STRING, achou AS INTEGER)
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
DECLARE FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
DECLARE SUB MontaClienteTeste (numero AS INTEGER, reg AS NoCliente)

CONST RRNPRIMEIRONO& = 1          ' tambem e SEMPRE o RRN da raiz - ver CADCLI1.BAS/docs/decisoes.md
CONST capacidadeCache% = 2        ' PEQUENO DE PROPOSITO - forca nos alem do cache (producao: 500, ver CADCLI1.BAS)
CONST RRNULTIMOCACHE& = RRNPRIMEIRONO& + capacidadeCache% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

DIM SHARED cacheCpf(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS STRING * 11
DIM SHARED cacheEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG
DIM SHARED cacheDir(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG

DIM SHARED regDisco AS NoCliente
DIM SHARED proxRRNLivre AS LONG
DIM SHARED qtdInseridos AS LONG
DIM SHARED qtdExcluidos AS LONG
DIM SHARED totalFalhas AS INTEGER

' ---------------------------------------------------------------------
' Harness de teste - cache de 2 nos, cadeia de 9 clientes (RRN3..9 so em disco)
' ---------------------------------------------------------------------

DIM reg AS NoCliente
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM sucesso AS INTEGER, reativado AS INTEGER
DIM i AS INTEGER

ON ERROR GOTO SemCliente3Dat
KILL "CLIENTE3.DAT"
GOTO ApagouCliente3Dat
SemCliente3Dat:
RESUME ApagouCliente3Dat
ApagouCliente3Dat:
ON ERROR GOTO 0

ON ERROR GOTO SemCliente3Log
KILL "CLIENTE3.LOG"
GOTO ApagouCliente3Log
SemCliente3Log:
RESUME ApagouCliente3Log
ApagouCliente3Log:
ON ERROR GOTO 0

OPEN "CLIENTE3.LOG" FOR OUTPUT AS #7
PRINT #7, "=== CADCLI3.BAS - cache pequeno (2), arvore alem do array ==="

ON ERROR GOTO TrataErro

CALL AbreArquivo
CALL Confere("cache capacidade = 2 (RRNULTIMOCACHE=2)", "2", LTRIM$(STR$(RRNULTIMOCACHE&)))

' --- insere 9 clientes em ordem crescente -> cadeia enviesada RRN1..9 ---
FOR i = 1 TO 9
  CALL MontaClienteTeste(i, reg)
  CALL InsereOuReativa(reg, sucesso, reativado)
  CALL Confere("insere cliente " + LTRIM$(STR$(i)), "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))
NEXT i

CALL Confere("qtdInseridos = 9 apos a cadeia", "9", LTRIM$(STR$(qtdInseridos)))
CALL Confere("proxRRNLivre = 9 apos a cadeia", "9", LTRIM$(STR$(proxRRNLivre)))

' --- busca na faixa cacheada (RRN 1 e 2) ---
CALL Busca(ChaveFixaCPF$("1"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha cliente 1 (raiz, RRN1, cache)", "-1,1", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))

CALL Busca(ChaveFixaCPF$("2"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha cliente 2 (RRN2, cache)", "-1,2", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))

' --- busca logo apos a borda do cache (RRN3 - primeiro no SO em disco) ---
CALL Busca(ChaveFixaCPF$("3"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha cliente 3 (RRN3, 1o alem do cache)", "-1,3", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("nome do cliente 3 bate (via arquivo)", "Cliente Teste 3", RTRIM$(reg.nome))

' --- busca no no mais profundo (RRN9 - atravessa 2 hops de cache + 7 so-disco) ---
CALL Busca(ChaveFixaCPF$("9"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha cliente 9 (RRN9, no mais fundo, 7 hops so-disco)", "-1,9", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("nome do cliente 9 bate (via arquivo)", "Cliente Teste 9", RTRIM$(reg.nome))

' --- busca inexistente maior que todos (percorre a cadeia inteira, ate o fim, so-disco) ---
CALL Busca(ChaveFixaCPF$("99"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("busca inexistente percorre cadeia toda ate nao achar", "0", LTRIM$(STR$(achou)))

' --- marca removido um no fora do cache (RRN6) ---
CALL MarcaRemovido(ChaveFixaCPF$("6"), achou)
CALL Confere("MarcaRemovido acha cliente 6 (RRN6, fora do cache)", "-1", LTRIM$(STR$(achou)))
CALL Busca(ChaveFixaCPF$("6"), achou, rrnAch, rrnPai, ladoPai)
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("excluido=1 do cliente 6 persistiu no arquivo", "1", LTRIM$(STR$(reg.excluido)))

' --- reativa o mesmo no fora do cache (grava direto no arquivo, sem cache) ---
CALL MontaClienteTeste(6, reg)
reg.nome = "Cliente Teste 6 Reativado"
CALL InsereOuReativa(reg, sucesso, reativado)
CALL Confere("reativa cliente 6 fora do cache", "-1,-1", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))
CALL Busca(ChaveFixaCPF$("6"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reativacao do cliente 6 manteve o mesmo RRN (nao criou no novo)", "6", LTRIM$(STR$(rrnAch)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("nome do cliente 6 atualizado apos reativacao fora do cache", "Cliente Teste 6 Reativado", RTRIM$(reg.nome))
CALL Confere("excluido=0 do cliente 6 apos reativacao fora do cache", "0", LTRIM$(STR$(reg.excluido)))

' --- insere um 10o cliente que vira filho de um PAI fora do cache (RRN9) ---
CALL MontaClienteTeste(10, reg)
CALL InsereOuReativa(reg, sucesso, reativado)
CALL Confere("insere cliente 10, pai fora do cache", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))
CALL CarregaRegistro(9, reg)
CALL Confere("ponteiro 'direita' do RRN9 (fora do cache) atualizado no arquivo", "10", LTRIM$(STR$(reg.direita)))
CALL Busca(ChaveFixaCPF$("10"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha cliente 10 (RRN10, pai fora do cache)", "-1,10", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))

' --- contadores finais ---
CALL Confere("qtdInseridos final = 10", "10", LTRIM$(STR$(qtdInseridos)))
CALL Confere("qtdExcluidos final = 0 (reativou o cliente 6)", "0", LTRIM$(STR$(qtdExcluidos)))

PRINT #7, ""
PRINT #7, "=== FIM. Falhas: "; totalFalhas; " ==="
CLOSE #1, #7

PRINT "CADCLI3 OK. Falhas: "; totalFalhas; ". Ver CLIENTE3.LOG"
SYSTEM

TrataErro:
PRINT #7, "*** ERRO EM RUNTIME (CADCLI3) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM

' ---------------------------------------------------------------------
' Monta um registro de cliente de teste a partir de um numero (1..10),
' pra nao repetir os 8 campos em cada insercao do harness. FUNCTION nao
' pode devolver TYPE em QBasic (so sufixo %/&/!/#/$) - por isso e SUB.
' ---------------------------------------------------------------------
SUB MontaClienteTeste (numero AS INTEGER, reg AS NoCliente)
  DIM n$
  n$ = LTRIM$(STR$(numero))
  reg.cpf = ChaveFixaCPF$(n$)
  reg.nome = "Cliente Teste " + n$
  reg.telefone = "1198765432" + RIGHT$(n$, 1)
  reg.endereco = "Rua Teste, " + n$
  reg.complemento = ""
  reg.cep = "00000-0" + RIGHT$("0" + n$, 2)   ' 7+2 = 9 chars, cabe em STRING*9
  reg.cidade = "Cidade Teste"
  reg.uf = "TT"
END SUB

' Normaliza CPF pra chave fixa de 11 digitos (zeros a esquerda)
FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
  ChaveFixaCPF$ = RIGHT$("00000000000" + cpfBruto, 11)
END FUNCTION

' Abre (ou cria) CLIENTE3.DAT. Deriva proxRRNLivre/qtdInseridos de LOF
' (sem registro de cabecalho) e espelha campos magros de navegacao pro
' cache SoA, tabulando qtdExcluidos no mesmo passe.
SUB AbreArquivo
  DIM r AS LONG, totalRegistros AS LONG

  OPEN "CLIENTE3.DAT" FOR RANDOM AS #1 LEN = LEN(regDisco)

  totalRegistros = LOF(1) \ LEN(regDisco)
  proxRRNLivre = totalRegistros
  qtdInseridos = totalRegistros
  qtdExcluidos = 0

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHE&
    IF r > totalRegistros THEN EXIT FOR
    GET #1, r, regDisco
    cacheCpf(r) = regDisco.cpf
    cacheEsq(r) = regDisco.esquerda
    cacheDir(r) = regDisco.direita
    IF regDisco.excluido = 1 THEN qtdExcluidos = qtdExcluidos + 1
  NEXT r

  IF totalRegistros > RRNULTIMOCACHE& THEN
    FOR r = RRNULTIMOCACHE& + 1 TO totalRegistros
      GET #1, r, regDisco
      IF regDisco.excluido = 1 THEN qtdExcluidos = qtdExcluidos + 1
    NEXT r
  END IF
END SUB

' Le so os campos de navegacao de um no: do cache SoA se o RRN estiver
' na faixa, senao do arquivo - AQUI e onde nos alem do cache caem
SUB LeNoNav (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHE& THEN
    cpf = cacheCpf(rrn)
    esq = cacheEsq(rrn)
    dir = cacheDir(rrn)
  ELSE
    GET #1, rrn, regDisco
    cpf = regDisco.cpf
    esq = regDisco.esquerda
    dir = regDisco.direita
  END IF
END SUB

' Le o registro completo direto do arquivo
SUB CarregaRegistro (rrn AS LONG, reg AS NoCliente)
  GET #1, rrn, reg
END SUB

' Grava um registro completo: sempre no arquivo; write-through no cache
' (so campos de navegacao) se o RRN estiver na faixa cacheada - fora
' dela, so o PUT acontece, sem tocar no array
SUB GravaRegistro (rrn AS LONG, reg AS NoCliente)
  PUT #1, rrn, reg

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHE& THEN
    cacheCpf(rrn) = reg.cpf
    cacheEsq(rrn) = reg.esquerda
    cacheDir(rrn) = reg.direita
  END IF
END SUB

' Busca por CPF, a partir da raiz (SEMPRE RRN 1)
SUB Busca (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
  DIM rrnAtual AS LONG, rrnPaiAtual AS LONG, lado AS INTEGER
  DIM cpfAtual AS STRING, esq AS LONG, dir AS LONG

  achou = 0
  rrnPaiAtual = 0
  lado = 0

  IF proxRRNLivre = 0 THEN
    rrnAchado = 0
    rrnPai = 0
    ladoPai = 0
    EXIT SUB
  END IF

  rrnAtual = RRNPRIMEIRONO&

  DO WHILE rrnAtual <> 0 AND achou = 0
    CALL LeNoNav(rrnAtual, cpfAtual, esq, dir)
    IF cpfProc = cpfAtual THEN
      achou = -1
      rrnAchado = rrnAtual
      rrnPai = rrnPaiAtual
      ladoPai = lado
    ELSEIF cpfProc < cpfAtual THEN
      rrnPaiAtual = rrnAtual
      lado = ESQUERDO%
      rrnAtual = esq
    ELSE
      rrnPaiAtual = rrnAtual
      lado = DIREITO%
      rrnAtual = dir
    END IF
  LOOP

  IF achou = 0 THEN
    rrnAchado = 0
    rrnPai = rrnPaiAtual
    ladoPai = lado
  END IF
END SUB

' Insere CPF novo, ou reaproveita (reativa) um no marcado como removido
SUB InsereOuReativa (reg AS NoCliente, sucesso AS INTEGER, reativado AS INTEGER)
  DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM novoRRN AS LONG
  DIM regPai AS NoCliente
  DIM regExistente AS NoCliente

  CALL Busca(reg.cpf, achou, rrnAch, rrnPai, ladoPai)

  IF achou THEN
    CALL CarregaRegistro(rrnAch, regExistente)
    IF regExistente.excluido = 0 THEN
      sucesso = 0
      reativado = 0
      EXIT SUB
    END IF

    regExistente.nome = reg.nome
    regExistente.telefone = reg.telefone
    regExistente.endereco = reg.endereco
    regExistente.complemento = reg.complemento
    regExistente.cep = reg.cep
    regExistente.cidade = reg.cidade
    regExistente.uf = reg.uf
    regExistente.excluido = 0
    CALL GravaRegistro(rrnAch, regExistente)

    qtdExcluidos = qtdExcluidos - 1
    sucesso = -1
    reativado = -1
    EXIT SUB
  END IF

  proxRRNLivre = proxRRNLivre + 1
  novoRRN = proxRRNLivre
  reg.esquerda = 0
  reg.direita = 0
  reg.excluido = 0
  CALL GravaRegistro(novoRRN, reg)

  IF rrnPai <> 0 THEN
    CALL CarregaRegistro(rrnPai, regPai)
    IF ladoPai = ESQUERDO% THEN
      regPai.esquerda = novoRRN
    ELSE
      regPai.direita = novoRRN
    END IF
    CALL GravaRegistro(rrnPai, regPai)
  END IF

  qtdInseridos = qtdInseridos + 1
  sucesso = -1
  reativado = 0
END SUB

' Marca logicamente removido (excluido=1)
SUB MarcaRemovido (cpfProc AS STRING, achou AS INTEGER)
  DIM rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM reg AS NoCliente

  CALL Busca(cpfProc, achou, rrnAch, rrnPai, ladoPai)
  IF achou THEN
    CALL CarregaRegistro(rrnAch, reg)
    IF reg.excluido = 0 THEN
      reg.excluido = 1
      CALL GravaRegistro(rrnAch, reg)
      qtdExcluidos = qtdExcluidos + 1
    END IF
  END IF
END SUB

' Assert simples: grava OK/FALHA no log e conta falhas
SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
  IF esperado = obtido THEN
    PRINT #7, "OK    - "; descricao
  ELSE
    PRINT #7, "FALHA - "; descricao; " | esperado=["; esperado; "] obtido=["; obtido; "]"
    totalFalhas = totalFalhas + 1
  END IF
END SUB
