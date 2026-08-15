' SISTEMA.BAS - menu principal, carrega indices primarios (cliente por
' CPF, produto por codigo de barras) em COMMON SHARED. Ver
' docs/arquitetura-tecnica.md, docs/decisoes.md, docs/armadilhas.md.
' Indice primario autoindexado: sem dadoRRN, no do arquivo = o dado.
' Layout de negocio de cliente e produto definidos (ver CLIENTES.BAS/
' PRODUTOS.BAS).

DECLARE SUB AbreIndiceCliente ()
DECLARE SUB AbreIndiceProduto ()

' REPETICAO: bloco CONST/COMMON SHARED do topo de arvore, replicado por
' exigencia do casamento posicional do COMMON - ver docs/duplicacoes.md
' e docs/armadilhas.md
CONST tamChaveCliente% = 11        ' CPF normalizado
CONST tamChaveProduto% = 13        ' codigo de barras EAN-13
CONST RRNPRIMEIRONO& = 1           ' tambem e SEMPRE o RRN da raiz - ver docs/decisoes.md

CONST capacidadeCacheCliente% = 500   ' teto real medido - ver docs/decisoes.md
CONST capacidadeCacheProduto% = 5041  ' teto de array dinamico (65536\13) - ver docs/decisoes.md

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1

' REPETICAO: layout do no primario de cliente - ver docs/duplicacoes.md
TYPE NoClientePrimario             ' 11+50+16+80+80+9+30+2+4+4+2 = 288 bytes/registro
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
  excluido    AS INTEGER           ' 0 = ativo, 1 = removido (logico, no fica na arvore)
END TYPE

' REPETICAO: layout do no primario de produto - ver docs/duplicacoes.md
TYPE NoProdutoPrimario              ' 13+80+4+4+4+2 = 107 bytes/registro
  codigoBarras AS STRING * 13
  descricao    AS STRING * 80
  preco        AS SINGLE
  esquerda     AS LONG
  direita      AS LONG
  excluido     AS INTEGER           ' 0 = ativo, 1 = removido (logico, no fica na arvore)
END TYPE

' Sem registro de cabecalho: raiz sempre RRNPRIMEIRONO&, proxRRNLivre/
' qtdInseridos derivados de LOF, qtdExcluidos tabulado na carga do cache
' - ver docs/decisoes.md (2026-08-14) e testes/CADCLI1.BAS/CADCLI3.BAS

' Arrays de cache sao DINAMICOS (sem bounds aqui, so tipo) - dimensionados
' via REDIM mais abaixo, 1x por sessao, dentro do guarda
' indicesCarregados. Estatico (DIM com bounds fixos) nao cabe: os dois
' juntos passam do teto de 64KB do DGROUP - ver docs/armadilhas.md.

' Replicar identico (mesma ordem, mesmas CONST) em todo modulo da
' corrente de CHAIN - ver docs/armadilhas.md.
COMMON SHARED proxRRNLivreCliente AS LONG, qtdInseridosCliente AS LONG, qtdExcluidosCliente AS LONG
COMMON SHARED proxRRNLivreProduto AS LONG, qtdInseridosProduto AS LONG, qtdExcluidosProduto AS LONG
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
    REDIM cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
    REDIM cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
    REDIM cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

    REDIM cacheProdutoChave(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS STRING * 13
    REDIM cacheProdutoEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG
    REDIM cacheProdutoDir(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG

    CALL AbreIndiceCliente
    CALL AbreIndiceProduto
    indicesCarregados = -1
  END IF

MenuPrincipal:
  CLS
  PRINT "=== Sistema de Controle de Lojinha ==="
  PRINT
  PRINT "1. Cadastro de clientes"
  PRINT "2. Cadastro de produtos"
  PRINT "0. Sair"
  PRINT
  INPUT "Opcao: ", opcao

  IF opcao = "1" THEN
    CHAIN "CLIENTES.BAS"
  ELSEIF opcao = "2" THEN
    CHAIN "PRODUTOS.BAS"
  ELSEIF opcao = "0" THEN
    CLOSE #1, #2
    SYSTEM
  ELSE
    GOTO MenuPrincipal
  END IF

END

' REPETICAO: carga do indice primario (arvore binaria autoindexada) do
' arquivo pra cache SoA em RAM - ver docs/duplicacoes.md
' Sem registro de cabecalho: deriva proxRRNLivre/qtdInseridos de LOF e
' tabula qtdExcluidos no mesmo passe que povoa o cache - docs/decisoes.md
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

  IF totalRegistros > RRNULTIMOCACHECliente& THEN
    FOR r = RRNULTIMOCACHECliente& + 1 TO totalRegistros
      GET #1, r, noDiscoCliente
      IF noDiscoCliente.excluido = 1 THEN qtdExcluidosCliente = qtdExcluidosCliente + 1
    NEXT r
  END IF
END SUB

' REPETICAO: carga do indice primario (arvore binaria autoindexada) do
' arquivo pra cache SoA em RAM - ver docs/duplicacoes.md
' Sem registro de cabecalho: deriva proxRRNLivre/qtdInseridos de LOF e
' tabula qtdExcluidos no mesmo passe que povoa o cache - docs/decisoes.md
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

  IF totalRegistros > RRNULTIMOCACHEProduto& THEN
    FOR r = RRNULTIMOCACHEProduto& + 1 TO totalRegistros
      GET #2, r, noDiscoProduto
      IF noDiscoProduto.excluido = 1 THEN qtdExcluidosProduto = qtdExcluidosProduto + 1
    NEXT r
  END IF
END SUB
