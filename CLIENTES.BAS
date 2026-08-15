' CLIENTES.BAS - cadastro de clientes: busca por CPF, insere, edita,
' remove logicamente. Replica o COMMON SHARED de SISTEMA.BAS na MESMA
' ordem, mesmas CONST - ver docs/armadilhas.md. CLIENTE.IDX (#1) e
' PRODUTO.IDX (#2) seguem abertos desde SISTEMA.BAS, nao reabrir aqui.
'
' REPETICAO: operacoes de arvore binaria (Busca/InsereOuReativa/
' MarcaRemovido/LeNoNav/GravaRegistro) por CPF, adaptadas dos prototipos
' testes/CADCLI1.BAS/CADCLI3.BAS - ver docs/duplicacoes.md.

' REPETICAO: layout do no primario de cliente - ver docs/duplicacoes.md
TYPE NoClientePrimario              ' 11+50+16+80+80+9+30+2+4+4+2 = 288 bytes/registro
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

DECLARE SUB LeNoNavCliente (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
DECLARE SUB CarregaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
DECLARE SUB GravaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
DECLARE SUB BuscaCliente (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB InsereOuReativaCliente (reg AS NoClientePrimario, sucesso AS INTEGER, reativado AS INTEGER)
DECLARE SUB MarcaRemovidoCliente (rrn AS LONG)
DECLARE SUB ApresentaCliente (reg AS NoClientePrimario)
DECLARE SUB PedeCamposNovoCliente (reg AS NoClientePrimario)
DECLARE SUB PedeCamposEdicaoCliente (reg AS NoClientePrimario)
DECLARE FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)

' REPETICAO: bloco CONST/DIM (arrays de cache)/COMMON SHARED do topo de
' arvore, replicado por exigencia do casamento posicional do COMMON -
' ver docs/duplicacoes.md e docs/armadilhas.md
CONST tamChaveCliente% = 11        ' CPF normalizado
CONST tamChaveProduto% = 13        ' codigo de barras EAN-13
CONST RRNPRIMEIRONO& = 1           ' tambem e SEMPRE o RRN da raiz - ver docs/decisoes.md

CONST capacidadeCacheCliente% = 50   ' precisa casar com SISTEMA.BAS
CONST capacidadeCacheProduto% = 100  ' idem

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

DIM cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
DIM cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
DIM cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

DIM cacheProdutoChave(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS STRING * 13
DIM cacheProdutoEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG
DIM cacheProdutoDir(RRNPRIMEIRONO& TO RRNULTIMOCACHEProduto&) AS LONG

COMMON SHARED proxRRNLivreCliente AS LONG, qtdInseridosCliente AS LONG, qtdExcluidosCliente AS LONG
COMMON SHARED proxRRNLivreProduto AS LONG, qtdInseridosProduto AS LONG, qtdExcluidosProduto AS LONG
COMMON SHARED cacheClienteChave() AS STRING * 11, cacheClienteEsq() AS LONG, cacheClienteDir() AS LONG
COMMON SHARED cacheProdutoChave() AS STRING * 13, cacheProdutoEsq() AS LONG, cacheProdutoDir() AS LONG
COMMON SHARED indicesCarregados AS INTEGER

DIM cpfDigitado AS STRING
DIM cpfBusca AS STRING
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM regCliente AS NoClientePrimario
DIM opcaoCliente AS STRING
DIM confirmaRemocao AS STRING
DIM sucessoIns AS INTEGER, reativadoIns AS INTEGER

  CLS
  PRINT "=== Cadastro de clientes ==="
  PRINT
  LINE INPUT "CPF (Enter para voltar): ", cpfDigitado

  IF RTRIM$(cpfDigitado) <> "" THEN
    cpfBusca = ChaveFixaCPF$(cpfDigitado)
    CALL BuscaCliente(cpfBusca, achou, rrnAch, rrnPai, ladoPai)

    IF achou THEN CALL CarregaRegistroCliente(rrnAch, regCliente)

    IF achou AND regCliente.excluido = 0 THEN
      PRINT
      CALL ApresentaCliente(regCliente)
      PRINT
      LINE INPUT "[E]ditar / [R]emover / [V]oltar: ", opcaoCliente
      opcaoCliente = UCASE$(opcaoCliente)

      IF opcaoCliente = "E" THEN
        PRINT
        CALL PedeCamposEdicaoCliente(regCliente)
        CALL GravaRegistroCliente(rrnAch, regCliente)
      ELSEIF opcaoCliente = "R" THEN
        LINE INPUT "Confirma remocao? [S/N]: ", confirmaRemocao
        IF UCASE$(confirmaRemocao) = "S" THEN CALL MarcaRemovidoCliente(rrnAch)
      END IF
    ELSE
      PRINT
      PRINT "Cliente nao encontrado!"
      LINE INPUT "[I]nserir / [V]oltar: ", opcaoCliente
      opcaoCliente = UCASE$(opcaoCliente)

      IF opcaoCliente = "I" THEN
        PRINT
        regCliente.cpf = cpfBusca
        CALL PedeCamposNovoCliente(regCliente)
        CALL InsereOuReativaCliente(regCliente, sucessoIns, reativadoIns)
      END IF
    END IF
  END IF

  CHAIN "SISTEMA.BAS"

' Mostra os dados de um cliente carregado do arquivo
SUB ApresentaCliente (reg AS NoClientePrimario)
  PRINT "CPF.........: "; reg.cpf
  PRINT "Nome........: "; RTRIM$(reg.nome)
  PRINT "Telefone....: "; RTRIM$(reg.telefone)
  PRINT "Endereco....: "; RTRIM$(reg.endereco)
  PRINT "Complemento.: "; RTRIM$(reg.complemento)
  PRINT "CEP.........: "; RTRIM$(reg.cep)
  PRINT "Cidade......: "; RTRIM$(reg.cidade)
  PRINT "UF..........: "; RTRIM$(reg.uf)
END SUB

' Pede os campos de um cliente novo. Nome e obrigatorio (repete ate
' preencher); demais campos aceitam ficar em branco. LINE INPUT em vez
' de INPUT - endereco/complemento podem conter virgula, que INPUT trata
' como separador de campo (confirmado no manual, ver docs/armadilhas.md)
SUB PedeCamposNovoCliente (reg AS NoClientePrimario)
  DIM temp AS STRING

  DO
    LINE INPUT "Nome (obrigatorio): ", temp
  LOOP WHILE RTRIM$(temp) = ""
  reg.nome = temp

  LINE INPUT "Telefone: ", temp
  reg.telefone = temp

  LINE INPUT "Endereco: ", temp
  reg.endereco = temp

  LINE INPUT "Complemento: ", temp
  reg.complemento = temp

  LINE INPUT "CEP: ", temp
  reg.cep = temp

  LINE INPUT "Cidade: ", temp
  reg.cidade = temp

  LINE INPUT "UF: ", temp
  reg.uf = temp
END SUB

' Pede os campos de edicao de um cliente existente. Enter em branco
' mantem o valor atual (QBasic nao tem edicao nativa de campo - ver
' docs/decisoes.md). Mostra o valor atual antes de cada prompt.
SUB PedeCamposEdicaoCliente (reg AS NoClientePrimario)
  DIM temp AS STRING

  PRINT "Nome atual........: "; RTRIM$(reg.nome)
  LINE INPUT "Novo nome (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.nome = temp

  PRINT "Telefone atual....: "; RTRIM$(reg.telefone)
  LINE INPUT "Novo telefone (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.telefone = temp

  PRINT "Endereco atual....: "; RTRIM$(reg.endereco)
  LINE INPUT "Novo endereco (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.endereco = temp

  PRINT "Complemento atual.: "; RTRIM$(reg.complemento)
  LINE INPUT "Novo complemento (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.complemento = temp

  PRINT "CEP atual.........: "; RTRIM$(reg.cep)
  LINE INPUT "Novo CEP (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.cep = temp

  PRINT "Cidade atual......: "; RTRIM$(reg.cidade)
  LINE INPUT "Nova cidade (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.cidade = temp

  PRINT "UF atual..........: "; RTRIM$(reg.uf)
  LINE INPUT "Nova UF (Enter mantem): ", temp
  IF RTRIM$(temp) <> "" THEN reg.uf = temp
END SUB

' Normaliza CPF pra chave fixa de 11 digitos (zeros a esquerda)
FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
  ChaveFixaCPF$ = RIGHT$("00000000000" + cpfBruto, 11)
END FUNCTION

' REPETICAO: le so os campos de navegacao de um no - do cache SoA se o
' RRN estiver na faixa, senao do arquivo - ver docs/duplicacoes.md
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

' Le o registro completo direto do arquivo
SUB CarregaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
  GET #1, rrn, reg
END SUB

' REPETICAO: grava um registro completo - sempre no arquivo; write-
' through no cache (so campos de navegacao) se o RRN estiver na faixa
' cacheada - ver docs/duplicacoes.md
SUB GravaRegistroCliente (rrn AS LONG, reg AS NoClientePrimario)
  PUT #1, rrn, reg

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHECliente& THEN
    cacheClienteChave(rrn) = reg.cpf
    cacheClienteEsq(rrn) = reg.esquerda
    cacheClienteDir(rrn) = reg.direita
  END IF
END SUB

' REPETICAO: busca por CPF, a partir da raiz (SEMPRE RRN 1) - ver
' docs/duplicacoes.md
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

' REPETICAO: insere CPF novo, ou reaproveita (reativa) um no marcado
' como removido - ver docs/duplicacoes.md
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

' REPETICAO: marca logicamente removido (excluido=1) - ver
' docs/duplicacoes.md. Recebe o RRN direto (ja veio de uma BuscaCliente
' na tela) em vez de buscar de novo por CPF.
SUB MarcaRemovidoCliente (rrn AS LONG)
  DIM reg AS NoClientePrimario

  CALL CarregaRegistroCliente(rrn, reg)
  IF reg.excluido = 0 THEN
    reg.excluido = 1
    CALL GravaRegistroCliente(rrn, reg)
    qtdExcluidosCliente = qtdExcluidosCliente + 1
  END IF
END SUB
