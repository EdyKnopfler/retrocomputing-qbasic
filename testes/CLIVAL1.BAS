' CLIVAL1.BAS - valida (headless, sem UI) as SUBs de arvore portadas
' para CLIENTES.BAS (BuscaCliente/InsereOuReativaCliente/
' MarcaRemovidoCliente/GravaRegistroCliente/CarregaRegistroCliente/
' LeNoNavCliente/ChaveFixaCPF$) - copia identica dos nomes e assinaturas
' usados em CLIENTES.BAS, so sem a camada de LINE INPUT/tela. Confirma
' que a renomeacao/porte a partir de testes/CADCLI1.BAS/CADCLI3.BAS nao
' introduziu erro de digitacao/wiring de COMMON. Descartavel.

TYPE NoClientePrimario              ' identico a CLIENTES.BAS/SISTEMA.BAS
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
  excluido    AS INTEGER
END TYPE

DECLARE SUB LeNoNavCliente (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
DECLARE SUB CarregaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
DECLARE SUB GravaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
DECLARE SUB BuscaCliente (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB InsereOuReativaCliente (reg AS NoClientePrimario, sucesso AS INTEGER, reativado AS INTEGER)
DECLARE SUB MarcaRemovidoCliente (rrn AS LONG)
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
DECLARE FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
DECLARE SUB MontaClienteTeste (numero AS INTEGER, reg AS NoClientePrimario)

CONST RRNPRIMEIRONO& = 1
CONST capacidadeCacheCliente% = 50
CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

DIM SHARED cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
DIM SHARED cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
DIM SHARED cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

DIM SHARED proxRRNLivreCliente AS LONG
DIM SHARED qtdInseridosCliente AS LONG
DIM SHARED qtdExcluidosCliente AS LONG
DIM SHARED totalFalhas AS INTEGER

DIM reg AS NoClientePrimario
DIM regRecarregado AS NoClientePrimario
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM sucesso AS INTEGER, reativado AS INTEGER

ON ERROR GOTO SemCliVal1Dat
KILL "CLIVAL1.DAT"
GOTO ApagouCliVal1Dat
SemCliVal1Dat:
RESUME ApagouCliVal1Dat
ApagouCliVal1Dat:
ON ERROR GOTO 0

ON ERROR GOTO SemCliVal1Log
KILL "CLIVAL1.LOG"
GOTO ApagouCliVal1Log
SemCliVal1Log:
RESUME ApagouCliVal1Log
ApagouCliVal1Log:
ON ERROR GOTO 0

OPEN "CLIVAL1.LOG" FOR OUTPUT AS #7
PRINT #7, "=== CLIVAL1.BAS - SUBs de CLIENTES.BAS sem a tela ==="

ON ERROR GOTO TrataErro

OPEN "CLIVAL1.DAT" FOR RANDOM AS #1 LEN = LEN(reg)
proxRRNLivreCliente = 0
qtdInseridosCliente = 0
qtdExcluidosCliente = 0

' --- insere 3 clientes ---
CALL MontaClienteTeste(1, reg)
CALL InsereOuReativaCliente(reg, sucesso, reativado)
CALL Confere("insere cliente 1", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

CALL MontaClienteTeste(2, reg)
CALL InsereOuReativaCliente(reg, sucesso, reativado)
CALL Confere("insere cliente 2", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

CALL MontaClienteTeste(3, reg)
CALL InsereOuReativaCliente(reg, sucesso, reativado)
CALL Confere("insere cliente 3", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

CALL Confere("qtdInseridosCliente = 3", "3", LTRIM$(STR$(qtdInseridosCliente)))
CALL Confere("proxRRNLivreCliente = 3", "3", LTRIM$(STR$(proxRRNLivreCliente)))

' --- duplicado ativo rejeitado ---
CALL MontaClienteTeste(1, reg)
CALL InsereOuReativaCliente(reg, sucesso, reativado)
CALL Confere("duplicado ativo (cliente 1) rejeitado", "0,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

' --- busca existente e inexistente ---
CALL BuscaCliente(ChaveFixaCPF$("1"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha cliente 1 (raiz)", "-1,1", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))

CALL BuscaCliente(ChaveFixaCPF$("999"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("nao acha cliente inexistente", "0", LTRIM$(STR$(achou)))

' --- grava direto (equivalente a Editar na tela) ---
CALL BuscaCliente(ChaveFixaCPF$("2"), achou, rrnAch, rrnPai, ladoPai)
CALL CarregaRegistroCliente(rrnAch, reg)
reg.nome = "Cliente Dois Editado"
CALL GravaRegistroCliente(rrnAch, reg)
CALL CarregaRegistroCliente(rrnAch, regRecarregado)
CALL Confere("edicao direta (GravaRegistroCliente) persistiu", "Cliente Dois Editado", RTRIM$(regRecarregado.nome))

' --- marca removido (cliente 3) ---
CALL BuscaCliente(ChaveFixaCPF$("3"), achou, rrnAch, rrnPai, ladoPai)
CALL MarcaRemovidoCliente(rrnAch)
CALL CarregaRegistroCliente(rrnAch, regRecarregado)
CALL Confere("MarcaRemovidoCliente marcou excluido=1", "1", LTRIM$(STR$(regRecarregado.excluido)))
CALL Confere("qtdExcluidosCliente = 1 apos remocao", "1", LTRIM$(STR$(qtdExcluidosCliente)))

' --- reativa cliente 3 com dados novos, mesmo RRN ---
CALL MontaClienteTeste(3, reg)
reg.nome = "Cliente Tres Reativado"
CALL InsereOuReativaCliente(reg, sucesso, reativado)
CALL Confere("reativa cliente 3", "-1,-1", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))
CALL BuscaCliente(ChaveFixaCPF$("3"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reativacao manteve o mesmo RRN (3)", "3", LTRIM$(STR$(rrnAch)))
CALL CarregaRegistroCliente(rrnAch, regRecarregado)
CALL Confere("nome atualizado apos reativacao", "Cliente Tres Reativado", RTRIM$(regRecarregado.nome))
CALL Confere("excluido=0 apos reativacao", "0", LTRIM$(STR$(regRecarregado.excluido)))
CALL Confere("qtdExcluidosCliente = 0 apos reativacao", "0", LTRIM$(STR$(qtdExcluidosCliente)))
CALL Confere("qtdInseridosCliente ainda = 3 (reativacao nao conta como nova)", "3", LTRIM$(STR$(qtdInseridosCliente)))

PRINT #7, ""
PRINT #7, "=== FIM. Falhas: "; totalFalhas; " ==="
CLOSE #1, #7

PRINT "CLIVAL1 OK. Falhas: "; totalFalhas; ". Ver CLIVAL1.LOG"
SYSTEM

TrataErro:
PRINT #7, "*** ERRO EM RUNTIME (CLIVAL1) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM

' Monta um registro de cliente de teste a partir de um numero
SUB MontaClienteTeste (numero AS INTEGER, reg AS NoClientePrimario)
  DIM n$
  n$ = LTRIM$(STR$(numero))
  reg.cpf = ChaveFixaCPF$(n$)
  reg.nome = "Cliente Teste " + n$
  reg.telefone = "1198765432" + RIGHT$(n$, 1)
  reg.endereco = "Rua Teste, " + n$
  reg.complemento = ""
  reg.cep = "00000-0" + RIGHT$("0" + n$, 2)
  reg.cidade = "Cidade Teste"
  reg.uf = "TT"
END SUB

' Normaliza CPF pra chave fixa de 11 digitos (zeros a esquerda)
FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
  ChaveFixaCPF$ = RIGHT$("00000000000" + cpfBruto, 11)
END FUNCTION

SUB LeNoNavCliente (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
  DIM regNav AS NoClientePrimario

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHECliente& THEN
    cpf = cacheClienteChave(rrn)
    esq = cacheClienteEsq(rrn)
    dir = cacheClienteDir(rrn)
  ELSE
    GET #1, rrn, regNav
    cpf = regNav.cpf
    esq = regNav.esquerda
    dir = regNav.direita
  END IF
END SUB

SUB CarregaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
  GET #1, rrn, reg
END SUB

SUB GravaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
  PUT #1, rrn, reg

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHECliente& THEN
    cacheClienteChave(rrn) = reg.cpf
    cacheClienteEsq(rrn) = reg.esquerda
    cacheClienteDir(rrn) = reg.direita
  END IF
END SUB

SUB BuscaCliente (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
  DIM rrnAtual AS LONG, rrnPaiAtual AS LONG, lado AS INTEGER
  DIM cpfAtual AS STRING, esq AS LONG, dir AS LONG

  achou = 0
  rrnPaiAtual = 0
  lado = 0

  IF proxRRNLivreCliente = 0 THEN
    rrnAchado = 0
    rrnPai = 0
    ladoPai = 0
    EXIT SUB
  END IF

  rrnAtual = RRNPRIMEIRONO&

  DO WHILE rrnAtual <> 0 AND achou = 0
    CALL LeNoNavCliente(rrnAtual, cpfAtual, esq, dir)
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

SUB InsereOuReativaCliente (reg AS NoClientePrimario, sucesso AS INTEGER, reativado AS INTEGER)
  DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM novoRRN AS LONG
  DIM regPai AS NoClientePrimario
  DIM regExistente AS NoClientePrimario

  CALL BuscaCliente(reg.cpf, achou, rrnAch, rrnPai, ladoPai)

  IF achou THEN
    CALL CarregaRegistroCliente(rrnAch, regExistente)
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
    CALL GravaRegistroCliente(rrnAch, regExistente)

    qtdExcluidosCliente = qtdExcluidosCliente - 1
    sucesso = -1
    reativado = -1
    EXIT SUB
  END IF

  proxRRNLivreCliente = proxRRNLivreCliente + 1
  novoRRN = proxRRNLivreCliente
  reg.esquerda = 0
  reg.direita = 0
  reg.excluido = 0
  CALL GravaRegistroCliente(novoRRN, reg)

  IF rrnPai <> 0 THEN
    CALL CarregaRegistroCliente(rrnPai, regPai)
    IF ladoPai = ESQUERDO% THEN
      regPai.esquerda = novoRRN
    ELSE
      regPai.direita = novoRRN
    END IF
    CALL GravaRegistroCliente(rrnPai, regPai)
  END IF

  qtdInseridosCliente = qtdInseridosCliente + 1
  sucesso = -1
  reativado = 0
END SUB

SUB MarcaRemovidoCliente (rrn AS LONG)
  DIM reg AS NoClientePrimario

  CALL CarregaRegistroCliente(rrn, reg)
  IF reg.excluido = 0 THEN
    reg.excluido = 1
    CALL GravaRegistroCliente(rrn, reg)
    qtdExcluidosCliente = qtdExcluidosCliente + 1
  END IF
END SUB

SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
  IF esperado = obtido THEN
    PRINT #7, "OK    - "; descricao
  ELSE
    PRINT #7, "FALHA - "; descricao; " | esperado=["; esperado; "] obtido=["; obtido; "]"
    totalFalhas = totalFalhas + 1
  END IF
END SUB
