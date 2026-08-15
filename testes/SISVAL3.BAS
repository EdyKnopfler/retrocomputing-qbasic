' SISVAL3.BAS - valida headless a mudanca de DIM estatico pra REDIM
' dinamico (500 clientes / 5041 produtos) contra os .IDX reais gravados
' pelo usuario, replicando a estrutura de SISTEMA.BAS. Ver docs/decisoes.md.

DECLARE SUB AbreIndiceCliente ()
DECLARE SUB AbreIndiceProduto ()

CONST tamChaveCliente% = 11
CONST tamChaveProduto% = 13
CONST RRNPRIMEIRONO& = 1

CONST capacidadeCacheCliente% = 500
CONST capacidadeCacheProduto% = 5041

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1

TYPE NoClientePrimario
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

TYPE NoProdutoPrimario
  codigoBarras AS STRING * 13
  descricao    AS STRING * 80
  preco        AS SINGLE
  esquerda     AS LONG
  direita      AS LONG
  excluido     AS INTEGER
END TYPE

COMMON SHARED proxRRNLivreCliente AS LONG, qtdInseridosCliente AS LONG, qtdExcluidosCliente AS LONG
COMMON SHARED proxRRNLivreProduto AS LONG, qtdInseridosProduto AS LONG, qtdExcluidosProduto AS LONG
COMMON SHARED cacheClienteChave() AS STRING * 11, cacheClienteEsq() AS LONG, cacheClienteDir() AS LONG
COMMON SHARED cacheProdutoChave() AS STRING * 13, cacheProdutoEsq() AS LONG, cacheProdutoDir() AS LONG
COMMON SHARED indicesCarregados AS INTEGER

DIM SHARED noDiscoCliente AS NoClientePrimario
DIM SHARED noDiscoProduto AS NoProdutoPrimario

REDIM cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
REDIM cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
REDIM cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

REDIM cacheProdutoChave(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS STRING * 13
REDIM cacheProdutoEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG
REDIM cacheProdutoDir(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG

OPEN "SISVAL3.LOG" FOR OUTPUT AS #9

CALL AbreIndiceCliente
CALL AbreIndiceProduto

PRINT #9, "qtdInseridosCliente: "; qtdInseridosCliente
PRINT #9, "qtdExcluidosCliente: "; qtdExcluidosCliente
PRINT #9, "proxRRNLivreCliente: "; proxRRNLivreCliente
PRINT #9, "cacheClienteChave(1): ["; cacheClienteChave(1); "]"
PRINT #9, "qtdInseridosProduto: "; qtdInseridosProduto
PRINT #9, "qtdExcluidosProduto: "; qtdExcluidosProduto
PRINT #9, "proxRRNLivreProduto: "; proxRRNLivreProduto
PRINT #9, "cacheProdutoChave(1): ["; cacheProdutoChave(1); "]"
IF qtdInseridosProduto >= 2 THEN
  PRINT #9, "cacheProdutoChave(2): ["; cacheProdutoChave(2); "]"
END IF
PRINT #9, "FRE(-1) apos carga: "; FRE(-1)
PRINT #9, "FIM_OK"

CLOSE #9
CLOSE #1, #2
SYSTEM

SUB AbreIndiceCliente
  DIM r AS LONG, totalRegistros AS LONG

  OPEN "CLIENTE.IDX" FOR RANDOM AS #1 LEN = LEN(noDiscoCliente)

  totalRegistros = LOF(1) \ LEN(noDiscoCliente)
  proxRRNLivreCliente = totalRegistros
  qtdInseridosCliente = totalRegistros
  qtdExcluidosCliente = 0

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&
    IF r > totalRegistros THEN EXIT FOR
    GET #1, r, noDiscoCliente
    cacheClienteChave(r) = noDiscoCliente.cpf
    cacheClienteEsq(r) = noDiscoCliente.esquerda
    cacheClienteDir(r) = noDiscoCliente.direita
    IF noDiscoCliente.excluido = 1 THEN qtdExcluidosCliente = qtdExcluidosCliente + 1
  NEXT r
END SUB

SUB AbreIndiceProduto
  DIM r AS LONG, totalRegistros AS LONG

  OPEN "PRODUTO.IDX" FOR RANDOM AS #2 LEN = LEN(noDiscoProduto)

  totalRegistros = LOF(2) \ LEN(noDiscoProduto)
  proxRRNLivreProduto = totalRegistros
  qtdInseridosProduto = totalRegistros
  qtdExcluidosProduto = 0

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&
    IF r > totalRegistros THEN EXIT FOR
    GET #2, r, noDiscoProduto
    cacheProdutoChave(r) = noDiscoProduto.codigoBarras
    cacheProdutoEsq(r) = noDiscoProduto.esquerda
    cacheProdutoDir(r) = noDiscoProduto.direita
    IF noDiscoProduto.excluido = 1 THEN qtdExcluidosProduto = qtdExcluidosProduto + 1
  NEXT r
END SUB
