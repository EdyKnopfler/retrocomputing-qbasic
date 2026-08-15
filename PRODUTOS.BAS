' PRODUTOS.BAS - cadastro de produtos: busca por codigo de barras
' (EAN-13), insere, edita, remove logicamente. Replica o COMMON SHARED
' de SISTEMA.BAS na MESMA ordem, mesmas CONST - ver docs/armadilhas.md.
' CLIENTE.IDX (#1) e PRODUTO.IDX (#2) seguem abertos desde SISTEMA.BAS,
' nao reabrir aqui.
'
' REPETICAO: operacoes de arvore binaria (Busca/InsereOuReativa/
' MarcaRemovido/LeNoNav/GravaRegistro) por codigo de barras, mesmo
' algoritmo de CLIENTES.BAS (por CPF) - ver docs/duplicacoes.md.

' REPETICAO: layout do no primario de produto - ver docs/duplicacoes.md
TYPE NoProdutoPrimario              ' 13+80+4+4+4+2 = 107 bytes/registro
  codigoBarras AS STRING * 13
  descricao    AS STRING * 80
  preco        AS SINGLE
  esquerda     AS LONG
  direita      AS LONG
  excluido     AS INTEGER          ' 0 = ativo, 1 = removido (logico, no fica na arvore)
END TYPE

DECLARE SUB LeNoNavProduto (rrn AS LONG, codigoBarras AS STRING, esq AS LONG, dir AS LONG)
DECLARE SUB CarregaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
DECLARE SUB GravaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
DECLARE SUB BuscaProduto (codigoProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB InsereOuReativaProduto (reg AS NoProdutoPrimario, sucesso AS INTEGER, reativado AS INTEGER)
DECLARE SUB MarcaRemovidoProduto (rrn AS LONG)
DECLARE SUB ApresentaProduto (reg AS NoProdutoPrimario)
DECLARE SUB PedeCamposNovoProduto (reg AS NoProdutoPrimario)
DECLARE SUB PedeCamposEdicaoProduto (reg AS NoProdutoPrimario)
DECLARE FUNCTION ChaveFixaBarras$ (codigoBruto AS STRING)

' REPETICAO: bloco CONST/COMMON SHARED do topo de arvore, replicado por
' exigencia do casamento posicional do COMMON - ver docs/duplicacoes.md
' e docs/armadilhas.md
CONST tamChaveCliente% = 11        ' CPF normalizado
CONST tamChaveProduto% = 13        ' codigo de barras EAN-13
CONST RRNPRIMEIRONO& = 1           ' tambem e SEMPRE o RRN da raiz - ver docs/decisoes.md

CONST capacidadeCacheCliente% = 500   ' precisa casar com SISTEMA.BAS
CONST capacidadeCacheProduto% = 5041  ' idem

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

' Arrays de cache sao dinamicos, dimensionados via REDIM 1x em
' SISTEMA.BAS - aqui so declara (COMMON SHARED), nunca redimensiona de
' novo (REDIM sempre zera - ver docs/armadilhas.md).

COMMON SHARED proxRRNLivreCliente AS LONG, qtdInseridosCliente AS LONG, qtdExcluidosCliente AS LONG
COMMON SHARED proxRRNLivreProduto AS LONG, qtdInseridosProduto AS LONG, qtdExcluidosProduto AS LONG
COMMON SHARED cacheClienteChave() AS STRING * 11, cacheClienteEsq() AS LONG, cacheClienteDir() AS LONG
COMMON SHARED cacheProdutoChave() AS STRING * 13, cacheProdutoEsq() AS LONG, cacheProdutoDir() AS LONG
COMMON SHARED indicesCarregados AS INTEGER

DIM codigoDigitado AS STRING
DIM codigoBusca AS STRING
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM regProduto AS NoProdutoPrimario
DIM opcaoProduto AS STRING
DIM confirmaRemocao AS STRING
DIM sucessoIns AS INTEGER, reativadoIns AS INTEGER

  CLS
  PRINT "=== Cadastro de produtos ==="
  PRINT
  LINE INPUT "Codigo de barras (Enter para voltar): ", codigoDigitado

  IF RTRIM$(codigoDigitado) <> "" THEN
    codigoBusca = ChaveFixaBarras$(codigoDigitado)
    CALL BuscaProduto(codigoBusca, achou, rrnAch, rrnPai, ladoPai)

    IF achou THEN CALL CarregaRegistroProduto(rrnAch, regProduto)

    IF achou AND regProduto.excluido = 0 THEN
      PRINT
      CALL ApresentaProduto(regProduto)
      PRINT
      LINE INPUT "[E]ditar / [R]emover / [V]oltar: ", opcaoProduto
      opcaoProduto = UCASE$(opcaoProduto)

      IF opcaoProduto = "E" THEN
        PRINT
        CALL PedeCamposEdicaoProduto(regProduto)
        CALL GravaRegistroProduto(rrnAch, regProduto)
      ELSEIF opcaoProduto = "R" THEN
        LINE INPUT "Confirma remocao? [S/N]: ", confirmaRemocao
        IF UCASE$(confirmaRemocao) = "S" THEN CALL MarcaRemovidoProduto(rrnAch)
      END IF
    ELSE
      PRINT
      PRINT "Produto nao encontrado!"
      LINE INPUT "[I]nserir / [V]oltar: ", opcaoProduto
      opcaoProduto = UCASE$(opcaoProduto)

      IF opcaoProduto = "I" THEN
        PRINT
        regProduto.codigoBarras = codigoBusca
        CALL PedeCamposNovoProduto(regProduto)
        CALL InsereOuReativaProduto(regProduto, sucessoIns, reativadoIns)
      END IF
    END IF
  END IF

  CHAIN "SISTEMA.BAS"

' Mostra os dados de um produto carregado do arquivo
SUB ApresentaProduto (reg AS NoProdutoPrimario)
  PRINT "Codigo de barras: "; reg.codigoBarras
  PRINT "Descricao.......: "; RTRIM$(reg.descricao)
  PRINT "Preco...........: "; reg.preco
END SUB

' Pede os campos de um produto novo. Descricao e preco sao obrigatorios
' (repete ate preencher/digitar valor > 0). LINE INPUT em vez de INPUT -
' mesmo motivo de CLIENTES.BAS (virgula quebraria INPUT); preco lido
' como texto e convertido com VAL() pra nao depender de INPUT num campo
' numerico (que trata Enter em branco como erro, quebrando o padrao
' "Enter mantem" usado na edicao - ver docs/armadilhas.md)
SUB PedeCamposNovoProduto (reg AS NoProdutoPrimario)
  DIM temp AS STRING

  DO
    LINE INPUT "Descricao (obrigatorio): ", temp
  LOOP WHILE RTRIM$(temp) = ""
  reg.descricao = temp

  DO
    LINE INPUT "Preco (obrigatorio, > 0): ", temp
  LOOP WHILE VAL(temp) <= 0
  reg.preco = VAL(temp)
END SUB

' Pede os campos de edicao de um produto existente. Enter em branco
' mantem o valor atual (QBasic nao tem edicao nativa de campo - ver
' docs/decisoes.md). Mostra o valor atual antes de cada prompt.
SUB PedeCamposEdicaoProduto (reg AS NoProdutoPrimario)
  DIM temp AS STRING

  PRINT "Descricao atual: "; RTRIM$(reg.descricao)
  LINE INPUT "Nova descricao (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.descricao = temp

  PRINT "Preco atual....: "; reg.preco
  LINE INPUT "Novo preco (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.preco = VAL(temp)
END SUB

' Normaliza codigo de barras pra chave fixa de 13 digitos (zeros a
' esquerda) - mesmo padrao de ChaveFixaCPF$ em CLIENTES.BAS
FUNCTION ChaveFixaBarras$ (codigoBruto AS STRING)
  ChaveFixaBarras$ = RIGHT$("0000000000000" + codigoBruto, 13)
END FUNCTION

' REPETICAO: le so os campos de navegacao de um no - do cache SoA se o
' RRN estiver na faixa, senao do arquivo - ver docs/duplicacoes.md
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

' Le o registro completo direto do arquivo
SUB CarregaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
  GET #2, rrn, reg
END SUB

' REPETICAO: grava um registro completo - sempre no arquivo; write-
' through no cache (so campos de navegacao) se o RRN estiver na faixa
' cacheada - ver docs/duplicacoes.md
SUB GravaRegistroProduto (rrn AS LONG, reg AS NoProdutoPrimario)
  PUT #2, rrn, reg

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHEProduto& THEN
    cacheProdutoChave(rrn) = reg.codigoBarras
    cacheProdutoEsq(rrn) = reg.esquerda
    cacheProdutoDir(rrn) = reg.direita
  END IF
END SUB

' REPETICAO: busca por codigo de barras, a partir da raiz (SEMPRE RRN 1)
' - ver docs/duplicacoes.md
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

' REPETICAO: insere codigo de barras novo, ou reaproveita (reativa) um
' no marcado como removido - ver docs/duplicacoes.md
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

' REPETICAO: marca logicamente removido (excluido=1) - ver
' docs/duplicacoes.md. Recebe o RRN direto (ja veio de uma BuscaProduto
' na tela) em vez de buscar de novo por codigo.
SUB MarcaRemovidoProduto (rrn AS LONG)
  DIM reg AS NoProdutoPrimario

  CALL CarregaRegistroProduto(rrn, reg)
  IF reg.excluido = 0 THEN
    reg.excluido = 1
    CALL GravaRegistroProduto(rrn, reg)
    qtdExcluidosProduto = qtdExcluidosProduto + 1
  END IF
END SUB
