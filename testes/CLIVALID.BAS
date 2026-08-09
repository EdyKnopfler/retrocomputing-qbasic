' CLIVALID.BAS - copia instrumentada de CLIENTES.BAS so para validar em
' QBASIC.EXE de verdade. Descartavel, nao e arquivo de producao.

CONST tamChaveCliente% = 11
CONST tamChaveProduto% = 13
CONST RRNHEADER& = 1
CONST RRNPRIMEIRONO& = 2

CONST capacidadeCacheCliente% = 50
CONST capacidadeCacheProduto% = 100

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1

TYPE CabecalhoIndice
  proxRRNLivre AS LONG
  raizRRN AS LONG
  qtdExcluidos AS LONG
  qtdInseridos AS LONG
END TYPE

DIM cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
DIM cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
DIM cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

DIM cacheProdutoChave(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS STRING * 13
DIM cacheProdutoEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG
DIM cacheProdutoDir(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG

COMMON SHARED cabecalhoCliente AS CabecalhoIndice, cabecalhoProduto AS CabecalhoIndice
COMMON SHARED cacheClienteChave() AS STRING * 11, cacheClienteEsq() AS LONG, cacheClienteDir() AS LONG
COMMON SHARED cacheProdutoChave() AS STRING * 13, cacheProdutoEsq() AS LONG, cacheProdutoDir() AS LONG
COMMON SHARED indicesCarregados AS INTEGER

ON ERROR GOTO TrataErro

OPEN "VALID.LOG" FOR APPEND AS #7
PRINT #7, "--- CLIVALID: entrada. indicesCarregados="; indicesCarregados
PRINT #7, "qtdInseridos="; cabecalhoCliente.qtdInseridos; " raizRRN="; cabecalhoCliente.raizRRN; " cacheClienteChave(2)=["; cacheClienteChave(2); "]"
PRINT #7, "Indo de volta para SISVALID.BAS"
CLOSE #7

CHAIN "SISVALID.BAS"

TrataErro:
OPEN "VALID.LOG" FOR APPEND AS #7
PRINT #7, "*** ERRO EM RUNTIME (CLIVALID) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM
