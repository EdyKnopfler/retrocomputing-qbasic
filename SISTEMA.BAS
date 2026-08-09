' SISTEMA.BAS - menu principal, carrega indices primarios (cliente por
' CPF, produto por codigo de barras) em COMMON SHARED. Ver
' docs/arquitetura-tecnica.md, docs/decisoes.md, docs/armadilhas.md.
' Indice primario autoindexado: sem dadoRRN, no do arquivo = o dado.
' Layout de negocio (nome etc.) ainda nao definido - so esqueleto.

DECLARE SUB AbreIndiceCliente ()
DECLARE SUB AbreIndiceProduto ()

CONST tamChaveCliente% = 11        ' CPF normalizado
CONST tamChaveProduto% = 13        ' codigo de barras EAN-13
CONST RRNHEADER& = 1
CONST RRNPRIMEIRONO& = 2

CONST capacidadeCacheCliente% = 50   ' pequeno de proposito no kickoff
CONST capacidadeCacheProduto% = 100  ' (producao: ver docs/arquitetura-tecnica.md)

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1

TYPE NoClientePrimario            ' 11+4+4+2 = 21 bytes/registro
  chave AS STRING * 11
  esquerda AS LONG
  direita AS LONG
  excluido AS INTEGER             ' 0 = ativo, 1 = excluido (reindexacao futura)
END TYPE

TYPE NoProdutoPrimario            ' 13+4+4+2 = 23 bytes/registro
  chave AS STRING * 13
  esquerda AS LONG
  direita AS LONG
  excluido AS INTEGER
END TYPE

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

' Replicar identico (mesma ordem, mesmas CONST) em todo modulo da
' corrente de CHAIN - ver docs/armadilhas.md.
COMMON SHARED cabecalhoCliente AS CabecalhoIndice, cabecalhoProduto AS CabecalhoIndice
COMMON SHARED cacheClienteChave() AS STRING * 11, cacheClienteEsq() AS LONG, cacheClienteDir() AS LONG
COMMON SHARED cacheProdutoChave() AS STRING * 13, cacheProdutoEsq() AS LONG, cacheProdutoDir() AS LONG
COMMON SHARED indicesCarregados AS INTEGER

DIM SHARED noDiscoCliente AS NoClientePrimario
DIM SHARED noDiscoProduto AS NoProdutoPrimario
DIM opcao AS STRING

  ' CHAIN reinicia o programa do topo - sem esta guarda, reabriria
  ' CLIENTE.IDX/PRODUTO.IDX como #1/#2 de novo ao voltar do menu. Ver
  ' docs/armadilhas.md.
  IF indicesCarregados = 0 THEN
    CALL AbreIndiceCliente
    CALL AbreIndiceProduto
    indicesCarregados = -1
  END IF

MenuPrincipal:
  CLS
  PRINT "=== Sistema de Controle de Lojinha ==="
  PRINT
  PRINT "1. Cadastro de clientes"
  PRINT "0. Sair"
  PRINT
  INPUT "Opcao: ", opcao

  IF opcao = "1" THEN
    CHAIN "CLIENTES.BAS"
  ELSEIF opcao = "0" THEN
    CLOSE #1, #2
    SYSTEM
  ELSE
    GOTO MenuPrincipal
  END IF

END

' ALGORITMO: carga do indice primario (arvore binaria autoindexada) do
' arquivo pra cache SoA em RAM - ver docs/algoritmos.md
SUB AbreIndiceCliente
  DIM r AS LONG

  OPEN "CLIENTE.IDX" FOR RANDOM AS #1 LEN = LEN(noDiscoCliente)

  IF LOF(1) = 0 THEN                 ' arquivo acabou de ser criado
    cabecalhoCliente.proxRRNLivre = RRNPRIMEIRONO& - 1
    cabecalhoCliente.raizRRN = 0
    cabecalhoCliente.qtdExcluidos = 0
    cabecalhoCliente.qtdInseridos = 0
    PUT #1, RRNHEADER&, cabecalhoCliente
  ELSE
    GET #1, RRNHEADER&, cabecalhoCliente
  END IF

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&
    GET #1, r, noDiscoCliente        ' GET alem do fim do arquivo retorna zerado
    cacheClienteChave(r) = noDiscoCliente.chave
    cacheClienteEsq(r) = noDiscoCliente.esquerda
    cacheClienteDir(r) = noDiscoCliente.direita
  NEXT r
END SUB

' ALGORITMO: carga do indice primario (arvore binaria autoindexada) do
' arquivo pra cache SoA em RAM - ver docs/algoritmos.md
SUB AbreIndiceProduto
  DIM r AS LONG

  OPEN "PRODUTO.IDX" FOR RANDOM AS #2 LEN = LEN(noDiscoProduto)

  IF LOF(2) = 0 THEN
    cabecalhoProduto.proxRRNLivre = RRNPRIMEIRONO& - 1
    cabecalhoProduto.raizRRN = 0
    cabecalhoProduto.qtdExcluidos = 0
    cabecalhoProduto.qtdInseridos = 0
    PUT #2, RRNHEADER&, cabecalhoProduto
  ELSE
    GET #2, RRNHEADER&, cabecalhoProduto
  END IF

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&
    GET #2, r, noDiscoProduto
    cacheProdutoChave(r) = noDiscoProduto.chave
    cacheProdutoEsq(r) = noDiscoProduto.esquerda
    cacheProdutoDir(r) = noDiscoProduto.direita
  NEXT r
END SUB
