' MEMFRE2.BAS - confirma FRE(-1) real com as arrays de cache no tamanho
' final proposto (500 clientes / 5041 produtos), replicando a estatica
' completa de SISTEMA.BAS. Ver docs/decisoes.md.

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


REDIM cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
REDIM cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
REDIM cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

REDIM cacheProdutoChave(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS STRING * 13
REDIM cacheProdutoEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG
REDIM cacheProdutoDir(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG


PRINT FRE(-1)

DIM SHARED noDiscoCliente AS NoClientePrimario
DIM SHARED noDiscoProduto AS NoProdutoPrimario
DIM opcao AS STRING

OPEN "MEMOUT2.TXT" FOR OUTPUT AS #1
PRINT #1, "FRE(-1) com cache 500 clientes / 5041 produtos: "; FRE(-1)
PRINT #1, "FRE(-2) stack: "; FRE(-2)
PRINT #1, "FRE("; ") strings: "; FRE("")
CLOSE #1
SYSTEM

