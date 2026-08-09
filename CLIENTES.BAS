' CLIENTES.BAS - cadastro de clientes. Placeholder: mostra contagem
' vinda do indice compartilhado (prova que o COMMON chegou), ENTER,
' CHAIN de volta. Ver docs/decisoes.md.
'
' Replica o COMMON SHARED de SISTEMA.BAS na MESMA ordem, mesmas CONST
' de capacidade - ver docs/armadilhas.md. CLIENTE.IDX (#1) e
' PRODUTO.IDX (#2) seguem abertos desde SISTEMA.BAS, nao reabrir aqui.

CONST tamChaveCliente% = 11        ' CPF normalizado
CONST tamChaveProduto% = 13        ' codigo de barras EAN-13
CONST RRNHEADER& = 1
CONST RRNPRIMEIRONO& = 2

CONST capacidadeCacheCliente% = 50   ' precisa casar com SISTEMA.BAS
CONST capacidadeCacheProduto% = 100  ' idem

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1

TYPE CabecalhoIndice              ' 4+4+4+4 = 16 bytes
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

DIM entrada AS STRING

CLS
PRINT "=== Cadastro de clientes (placeholder) ==="
PRINT
PRINT "Clientes cadastrados (via indice compartilhado): "; cabecalhoCliente.qtdInseridos
PRINT
INPUT "ENTER para voltar ao menu: ", entrada

CHAIN "SISTEMA.BAS"
