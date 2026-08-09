' ARVDISCO.BAS
' Prototipo: indice em arvore binaria (chave-string) com backing em
' arquivo randomico (GET/PUT). Cache SoA em RAM para o topo da arvore,
' escrita write-through via LeNo/GravaNo. Ver docs/decisoes.md e
' docs/arquitetura-tecnica.md no repo SISTEMA.
'
' Representa o caso de indice SECUNDARIO (com campo dadoRRN explicito).
' O indice PRIMARIO autoindexado (sem dadoRRN) fica para outro prototipo.

DECLARE SUB AbreIndice ()
DECLARE SUB LeNo (rrn AS LONG, chave AS STRING, esq AS LONG, dir AS LONG, dado AS LONG)
DECLARE SUB GravaNo (rrn AS LONG, chave AS STRING, esq AS LONG, dir AS LONG, dado AS LONG)
DECLARE SUB Busca (chaveProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB Insere (chaveNova AS STRING, dadoNovo AS LONG, sucesso AS INTEGER)
DECLARE FUNCTION ChaveFixa$ (id AS INTEGER)

CONST tamChave% = 13              ' EAN-13 / CPF normalizado
CONST ESQUERDO% = 1, DIREITO% = 2
CONST RRNHEADER& = 1
CONST RRNPRIMEIRONO& = 2
CONST capacidadeCache% = 50       ' pequeno de proposito no teste (producao: ~5041)
CONST RRNULTIMOCACHE& = RRNPRIMEIRONO& + capacidadeCache% - 1

TYPE NoIndice                     ' 13+4+4+4+2 = 27 bytes/registro
  chave AS STRING * 13
  esquerda AS LONG
  direita AS LONG
  dadoRRN AS LONG
  excluido AS INTEGER             ' 0 = ativo, 1 = excluido (uso futuro em reindexacao)
END TYPE

TYPE CabecalhoIndice              ' 4+4+4+4 = 16 bytes, cabe no mesmo LEN do NoIndice
  proxRRNLivre AS LONG
  raizRRN AS LONG
  qtdExcluidos AS LONG
  qtdInseridos AS LONG
END TYPE

DIM SHARED noDisco AS NoIndice
DIM SHARED cabecalho AS CabecalhoIndice

DIM SHARED cacheChave(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS STRING * 13
DIM SHARED cacheEsquerda(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG
DIM SHARED cacheDireita(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG
DIM SHARED cacheDadoRRN(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG

DIM SHARED contLeiturasCache AS LONG
DIM SHARED contLeiturasArquivo AS LONG
DIM SHARED existeArquivoIdx AS INTEGER

' ---------------------------------------------------------------------
' Harness de teste
' ---------------------------------------------------------------------

DIM nomeLog$, nomeCsv$, id AS INTEGER, valor AS SINGLE, leituraNome AS STRING
DIM chave AS STRING, achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM sucesso AS INTEGER, contDados AS LONG
DIM primeiraChave AS STRING, ultimaChave AS STRING
DIM linhasLidas AS LONG, inseridos AS LONG, duplicados AS LONG

nomeLog$ = "LOG.TXT"
nomeCsv$ = "VENDAS1.CSV"

OPEN nomeLog$ FOR OUTPUT AS #2
PRINT #2, "=== ARVDISCO.BAS - execucao ==="

' ON ERROR so vale no programa principal (nao dentro de SUB/FUNCTION) -
' testa aqui se PRODUTO.IDX ja existe e guarda o resultado numa SHARED
' pra AbreIndice so ler.
existeArquivoIdx = -1
ON ERROR GOTO NaoExisteIdx
OPEN "PRODUTO.IDX" FOR INPUT AS #9
CLOSE #9
GOTO AbriuTesteIdx
NaoExisteIdx:
existeArquivoIdx = 0
RESUME AbriuTesteIdx
AbriuTesteIdx:
ON ERROR GOTO 0

' Handler global para o resto do programa: se der erro em runtime,
' grava ERR/ERL no LOG.TXT em vez de travar num dialogo modal do QBasic.
ON ERROR GOTO TrataErro

CALL AbreIndice
PRINT #2, "AbreIndice OK. proxRRNLivre="; cabecalho.proxRRNLivre; " raizRRN="; cabecalho.raizRRN; " qtdInseridos="; cabecalho.qtdInseridos

contDados = cabecalho.qtdInseridos  ' continua contador sintetico entre execucoes
linhasLidas = 0: inseridos = 0: duplicados = 0
primeiraChave = "": ultimaChave = ""

PRINT "Lendo "; nomeCsv$; " ..."

OPEN nomeCsv$ FOR INPUT AS #3
DO WHILE NOT EOF(3)
  INPUT #3, leituraNome, id, valor
  linhasLidas = linhasLidas + 1
  IF linhasLidas MOD 200 = 0 THEN PRINT "."; ' na tela, so pra mostrar que esta vivo
  chave = ChaveFixa$(id)

  CALL Busca(chave, achou, rrnAch, rrnPai, ladoPai)
  IF achou = 0 THEN
    contDados = contDados + 1
    CALL Insere(chave, contDados, sucesso)
    IF sucesso THEN
      inseridos = inseridos + 1
      IF primeiraChave = "" THEN primeiraChave = chave
      ultimaChave = chave
    END IF
  ELSE
    duplicados = duplicados + 1
  END IF
LOOP
CLOSE #3

PRINT #2, "Linhas lidas do CSV: "; linhasLidas
PRINT #2, "Inseridos nesta execucao: "; inseridos
PRINT #2, "Duplicados (ja existiam): "; duplicados
PRINT #2, "proxRRNLivre apos carga: "; cabecalho.proxRRNLivre
PRINT #2, "raizRRN apos carga: "; cabecalho.raizRRN

' Reseta contadores para medir soh as 3 buscas de verificacao
contLeiturasCache = 0
contLeiturasArquivo = 0

PRINT #2, ""
PRINT #2, "=== Buscas de verificacao ==="

IF primeiraChave <> "" THEN
  CALL Busca(primeiraChave, achou, rrnAch, rrnPai, ladoPai)
  PRINT #2, "Busca 1a chave inserida ("; primeiraChave; "): achou="; achou; " rrn="; rrnAch
END IF

IF ultimaChave <> "" THEN
  CALL Busca(ultimaChave, achou, rrnAch, rrnPai, ladoPai)
  PRINT #2, "Busca ultima chave inserida ("; ultimaChave; "): achou="; achou; " rrn="; rrnAch
END IF

CALL Busca("9999999999999", achou, rrnAch, rrnPai, ladoPai)
PRINT #2, "Busca chave inexistente (9999999999999): achou="; achou

PRINT #2, ""
PRINT #2, "Leituras via cache (RAM): "; contLeiturasCache
PRINT #2, "Leituras via arquivo (GET): "; contLeiturasArquivo
PRINT #2, "Capacidade de cache: "; capacidadeCache%; " (RRN "; RRNPRIMEIRONO&; " a "; RRNULTIMOCACHE&; ")"

CLOSE #1  ' indice
CLOSE #2  ' log

PRINT
PRINT "FIM - OK. Ver LOG.TXT"
SYSTEM

TrataErro:
PRINT
PRINT "*** ERRO EM RUNTIME *** ERR="; ERR; " ERL="; ERL
PRINT #2, "*** ERRO EM RUNTIME *** ERR="; ERR; " ERL="; ERL
CLOSE #2
SYSTEM

' ---------------------------------------------------------------------
' Normaliza um id% (INTEGER) para chave fixa de 13 digitos
' ---------------------------------------------------------------------
FUNCTION ChaveFixa$ (id AS INTEGER)
  DIM s$
  s$ = LTRIM$(STR$(id))
  ChaveFixa$ = RIGHT$("0000000000000" + s$, 13)
END FUNCTION

' ---------------------------------------------------------------------
' Abre (ou cria) o arquivo de indice e espelha o topo para o cache SoA
' ---------------------------------------------------------------------
SUB AbreIndice
  DIM r AS LONG

  OPEN "PRODUTO.IDX" FOR RANDOM AS #1 LEN = LEN(noDisco)

  IF existeArquivoIdx = 0 THEN
    cabecalho.proxRRNLivre = RRNPRIMEIRONO& - 1
    cabecalho.raizRRN = 0
    cabecalho.qtdExcluidos = 0
    cabecalho.qtdInseridos = 0
    PUT #1, RRNHEADER&, cabecalho
  ELSE
    GET #1, RRNHEADER&, cabecalho
  END IF

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHE&
    GET #1, r, noDisco               ' GET alem do fim do arquivo retorna zerado
    cacheChave(r) = noDisco.chave
    cacheEsquerda(r) = noDisco.esquerda
    cacheDireita(r) = noDisco.direita
    cacheDadoRRN(r) = noDisco.dadoRRN
  NEXT r
END SUB

' ---------------------------------------------------------------------
' Le um no: do cache SoA se o RRN estiver na faixa, senao do arquivo
' ---------------------------------------------------------------------
SUB LeNo (rrn AS LONG, chave AS STRING, esq AS LONG, dir AS LONG, dado AS LONG)
  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHE& THEN
    chave = cacheChave(rrn)
    esq = cacheEsquerda(rrn)
    dir = cacheDireita(rrn)
    dado = cacheDadoRRN(rrn)
    contLeiturasCache = contLeiturasCache + 1
  ELSE
    GET #1, rrn, noDisco
    chave = noDisco.chave
    esq = noDisco.esquerda
    dir = noDisco.direita
    dado = noDisco.dadoRRN
    contLeiturasArquivo = contLeiturasArquivo + 1
  END IF
END SUB

' ---------------------------------------------------------------------
' Grava um no: sempre no arquivo; write-through no cache se aplicavel
' ---------------------------------------------------------------------
SUB GravaNo (rrn AS LONG, chave AS STRING, esq AS LONG, dir AS LONG, dado AS LONG)
  noDisco.chave = chave
  noDisco.esquerda = esq
  noDisco.direita = dir
  noDisco.dadoRRN = dado
  noDisco.excluido = 0
  PUT #1, rrn, noDisco

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHE& THEN
    cacheChave(rrn) = chave
    cacheEsquerda(rrn) = esq
    cacheDireita(rrn) = dir
    cacheDadoRRN(rrn) = dado
  END IF
END SUB

' ---------------------------------------------------------------------
' Busca por chave, a partir da raiz. Devolve pai + lado, para permitir
' insercao subsequente sem precisar buscar de novo.
' ---------------------------------------------------------------------
SUB Busca (chaveProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
  DIM rrnAtual AS LONG, rrnPaiAtual AS LONG, lado AS INTEGER
  DIM chaveAtual AS STRING, esq AS LONG, dir AS LONG, dado AS LONG

  rrnAtual = cabecalho.raizRRN
  rrnPaiAtual = 0
  lado = 0
  achou = 0

  DO WHILE rrnAtual <> 0 AND achou = 0
    CALL LeNo(rrnAtual, chaveAtual, esq, dir, dado)
    IF chaveProc = chaveAtual THEN
      achou = -1
      rrnAchado = rrnAtual
      rrnPai = rrnPaiAtual
      ladoPai = lado
    ELSEIF chaveProc < chaveAtual THEN
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

' ---------------------------------------------------------------------
' Insere nova chave (assume que Busca ja confirmou que nao existe).
' Alocacao linear via cabecalho.proxRRNLivre.
' ---------------------------------------------------------------------
SUB Insere (chaveNova AS STRING, dadoNovo AS LONG, sucesso AS INTEGER)
  DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM novoRRN AS LONG
  DIM chavePai AS STRING, esqPai AS LONG, dirPai AS LONG, dadoPai AS LONG

  CALL Busca(chaveNova, achou, rrnAch, rrnPai, ladoPai)
  IF achou THEN
    sucesso = 0
    EXIT SUB
  END IF

  cabecalho.proxRRNLivre = cabecalho.proxRRNLivre + 1
  novoRRN = cabecalho.proxRRNLivre
  CALL GravaNo(novoRRN, chaveNova, 0, 0, dadoNovo)

  IF rrnPai = 0 THEN
    cabecalho.raizRRN = novoRRN
  ELSE
    CALL LeNo(rrnPai, chavePai, esqPai, dirPai, dadoPai)
    IF ladoPai = ESQUERDO% THEN
      CALL GravaNo(rrnPai, chavePai, novoRRN, dirPai, dadoPai)
    ELSE
      CALL GravaNo(rrnPai, chavePai, esqPai, novoRRN, dadoPai)
    END IF
  END IF

  cabecalho.qtdInseridos = cabecalho.qtdInseridos + 1
  PUT #1, RRNHEADER&, cabecalho
  sucesso = -1
END SUB
