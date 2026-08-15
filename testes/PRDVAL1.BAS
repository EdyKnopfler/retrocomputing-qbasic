' PRDVAL1.BAS - checagem headless minima do que e novo em PRODUTOS.BAS
' em relacao a CLIENTES.BAS (algoritmo de arvore ja provado, nao repete
' a suite inteira): campo SINGLE (preco) sobrevivendo ao GET/PUT, e
' conversao VAL() na insercao/edicao. Descartavel.

TYPE NoProdutoPrimario              ' identico a PRODUTOS.BAS/SISTEMA.BAS
  codigoBarras AS STRING * 13
  descricao    AS STRING * 80
  preco        AS SINGLE
  esquerda     AS LONG
  direita      AS LONG
  excluido     AS INTEGER
END TYPE

DECLARE SUB LeNoNavProduto (rrn AS LONG, codigoBarras AS STRING, esq AS LONG, dir AS LONG)
DECLARE SUB CarregaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
DECLARE SUB GravaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
DECLARE SUB BuscaProduto (codigoProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB InsereOuReativaProduto (reg AS NoProdutoPrimario, sucesso AS INTEGER, reativado AS INTEGER)
DECLARE SUB MarcaRemovidoProduto (rrn AS LONG)
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
DECLARE FUNCTION ChaveFixaBarras$ (codigoBruto AS STRING)

CONST RRNPRIMEIRONO& = 1
CONST capacidadeCacheProduto% = 100
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

DIM SHARED cacheProdutoChave(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS STRING * 13
DIM SHARED cacheProdutoEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG
DIM SHARED cacheProdutoDir(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG

DIM SHARED proxRRNLivreProduto AS LONG
DIM SHARED qtdInseridosProduto AS LONG
DIM SHARED qtdExcluidosProduto AS LONG
DIM SHARED totalFalhas AS INTEGER

DIM reg AS NoProdutoPrimario
DIM regRecarregado AS NoProdutoPrimario
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM sucesso AS INTEGER, reativado AS INTEGER

ON ERROR GOTO SemPrdVal1Dat
KILL "PRDVAL1.DAT"
GOTO ApagouPrdVal1Dat
SemPrdVal1Dat:
RESUME ApagouPrdVal1Dat
ApagouPrdVal1Dat:
ON ERROR GOTO 0

ON ERROR GOTO SemPrdVal1Log
KILL "PRDVAL1.LOG"
GOTO ApagouPrdVal1Log
SemPrdVal1Log:
RESUME ApagouPrdVal1Log
ApagouPrdVal1Log:
ON ERROR GOTO 0

OPEN "PRDVAL1.LOG" FOR OUTPUT AS #7
PRINT #7, "=== PRDVAL1.BAS - campo SINGLE (preco) via SUBs de PRODUTOS.BAS ==="

ON ERROR GOTO TrataErro

OPEN "PRDVAL1.DAT" FOR RANDOM AS #2 LEN = LEN(reg)
proxRRNLivreProduto = 0
qtdInseridosProduto = 0
qtdExcluidosProduto = 0

' --- insere produto com preco fracionario (equivalente a VAL("12.9")) ---
reg.codigoBarras = ChaveFixaBarras$("7891000100103")
reg.descricao = "Arroz 5kg"
reg.preco = VAL("12.9")
CALL InsereOuReativaProduto(reg, sucesso, reativado)
CALL Confere("insere produto 1", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

' --- segundo produto ---
reg.codigoBarras = ChaveFixaBarras$("7891000100110")
reg.descricao = "Feijao 1kg"
reg.preco = VAL("7.49")
CALL InsereOuReativaProduto(reg, sucesso, reativado)
CALL Confere("insere produto 2", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

' --- duplicado ativo rejeitado ---
reg.codigoBarras = ChaveFixaBarras$("7891000100103")
reg.descricao = "Arroz 5kg (duplicado)"
reg.preco = VAL("99.9")
CALL InsereOuReativaProduto(reg, sucesso, reativado)
CALL Confere("duplicado ativo rejeitado", "0,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

' --- busca e confere preco/descricao sobreviveram ao GET/PUT ---
CALL BuscaProduto(ChaveFixaBarras$("7891000100103"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("acha produto 1 (raiz)", "-1,1", LTRIM$(STR$(achou)) + "," + LTRIM$(STR$(rrnAch)))
CALL CarregaRegistroProduto(rrnAch, regRecarregado)
CALL Confere("descricao do produto 1 bate", "Arroz 5kg", RTRIM$(regRecarregado.descricao))
CALL Confere("preco do produto 1 bate (SINGLE via GET/PUT)", "12.9", LTRIM$(STR$(regRecarregado.preco)))

' --- VAL() de texto invalido/vazio retorna 0 (confirmado no manual) ---
CALL Confere("VAL de texto vazio = 0", "0", LTRIM$(STR$(VAL(""))))
CALL Confere("VAL de texto nao-numerico = 0", "0", LTRIM$(STR$(VAL("abc"))))

' --- edicao direta (equivalente a Editar->Enter mantem descricao, novo preco) ---
CALL BuscaProduto(ChaveFixaBarras$("7891000100110"), achou, rrnAch, rrnPai, ladoPai)
CALL CarregaRegistroProduto(rrnAch, reg)
reg.preco = VAL("8.20")
CALL GravaRegistroProduto(rrnAch, reg)
CALL CarregaRegistroProduto(rrnAch, regRecarregado)
CALL Confere("preco editado persistiu", "8.2", LTRIM$(STR$(regRecarregado.preco)))
CALL Confere("descricao nao mudou (so preco foi editado)", "Feijao 1kg", RTRIM$(regRecarregado.descricao))

' --- remove e reativa produto 2 ---
CALL MarcaRemovidoProduto(rrnAch)
CALL CarregaRegistroProduto(rrnAch, regRecarregado)
CALL Confere("excluido=1 apos remocao", "1", LTRIM$(STR$(regRecarregado.excluido)))

reg.codigoBarras = ChaveFixaBarras$("7891000100110")
reg.descricao = "Feijao 1kg (reativado)"
reg.preco = VAL("6.99")
CALL InsereOuReativaProduto(reg, sucesso, reativado)
CALL Confere("reativa produto 2", "-1,-1", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))
CALL BuscaProduto(ChaveFixaBarras$("7891000100110"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reativacao manteve o mesmo RRN (2)", "2", LTRIM$(STR$(rrnAch)))
CALL CarregaRegistroProduto(rrnAch, regRecarregado)
CALL Confere("preco atualizado apos reativacao", "6.99", LTRIM$(STR$(regRecarregado.preco)))
CALL Confere("excluido=0 apos reativacao", "0", LTRIM$(STR$(regRecarregado.excluido)))

PRINT #7, ""
PRINT #7, "=== FIM. Falhas: "; totalFalhas; " ==="
CLOSE #2, #7

PRINT "PRDVAL1 OK. Falhas: "; totalFalhas; ". Ver PRDVAL1.LOG"
SYSTEM

TrataErro:
PRINT #7, "*** ERRO EM RUNTIME (PRDVAL1) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM

FUNCTION ChaveFixaBarras$ (codigoBruto AS STRING)
  ChaveFixaBarras$ = RIGHT$("0000000000000" + codigoBruto, 13)
END FUNCTION

SUB LeNoNavProduto (rrn AS LONG, codigoBarras AS STRING, esq AS LONG, dir AS LONG)
  DIM regNav AS NoProdutoPrimario

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHEProduto& THEN
    codigoBarras = cacheProdutoChave(rrn)
    esq = cacheProdutoEsq(rrn)
    dir = cacheProdutoDir(rrn)
  ELSE
    GET #2, rrn, regNav
    codigoBarras = regNav.codigoBarras
    esq = regNav.esquerda
    dir = regNav.direita
  END IF
END SUB

SUB CarregaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
  GET #2, rrn, reg
END SUB

SUB GravaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
  PUT #2, rrn, reg

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHEProduto& THEN
    cacheProdutoChave(rrn) = reg.codigoBarras
    cacheProdutoEsq(rrn) = reg.esquerda
    cacheProdutoDir(rrn) = reg.direita
  END IF
END SUB

SUB BuscaProduto (codigoProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
  DIM rrnAtual AS LONG, rrnPaiAtual AS LONG, lado AS INTEGER
  DIM codigoAtual AS STRING, esq AS LONG, dir AS LONG

  achou = 0
  rrnPaiAtual = 0
  lado = 0

  IF proxRRNLivreProduto = 0 THEN
    rrnAchado = 0
    rrnPai = 0
    ladoPai = 0
    EXIT SUB
  END IF

  rrnAtual = RRNPRIMEIRONO&

  DO WHILE rrnAtual <> 0 AND achou = 0
    CALL LeNoNavProduto(rrnAtual, codigoAtual, esq, dir)
    IF codigoProc = codigoAtual THEN
      achou = -1
      rrnAchado = rrnAtual
      rrnPai = rrnPaiAtual
      ladoPai = lado
    ELSEIF codigoProc < codigoAtual THEN
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

SUB InsereOuReativaProduto (reg AS NoProdutoPrimario, sucesso AS INTEGER, reativado AS INTEGER)
  DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM novoRRN AS LONG
  DIM regPai AS NoProdutoPrimario
  DIM regExistente AS NoProdutoPrimario

  CALL BuscaProduto(reg.codigoBarras, achou, rrnAch, rrnPai, ladoPai)

  IF achou THEN
    CALL CarregaRegistroProduto(rrnAch, regExistente)
    IF regExistente.excluido = 0 THEN
      sucesso = 0
      reativado = 0
      EXIT SUB
    END IF

    regExistente.descricao = reg.descricao
    regExistente.preco = reg.preco
    regExistente.excluido = 0
    CALL GravaRegistroProduto(rrnAch, regExistente)

    qtdExcluidosProduto = qtdExcluidosProduto - 1
    sucesso = -1
    reativado = -1
    EXIT SUB
  END IF

  proxRRNLivreProduto = proxRRNLivreProduto + 1
  novoRRN = proxRRNLivreProduto
  reg.esquerda = 0
  reg.direita = 0
  reg.excluido = 0
  CALL GravaRegistroProduto(novoRRN, reg)

  IF rrnPai <> 0 THEN
    CALL CarregaRegistroProduto(rrnPai, regPai)
    IF ladoPai = ESQUERDO% THEN
      regPai.esquerda = novoRRN
    ELSE
      regPai.direita = novoRRN
    END IF
    CALL GravaRegistroProduto(rrnPai, regPai)
  END IF

  qtdInseridosProduto = qtdInseridosProduto + 1
  sucesso = -1
  reativado = 0
END SUB

SUB MarcaRemovidoProduto (rrn AS LONG)
  DIM reg AS NoProdutoPrimario

  CALL CarregaRegistroProduto(rrn, reg)
  IF reg.excluido = 0 THEN
    reg.excluido = 1
    CALL GravaRegistroProduto(rrn, reg)
    qtdExcluidosProduto = qtdExcluidosProduto + 1
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
