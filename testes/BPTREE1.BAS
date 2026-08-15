' ===============================
' MODULO: Buffer
' - Mantem um buffer binario fixo (512 bytes)
'
' ESTADO:
' - BufferString
' ===============================

DIM SHARED BufferString AS STRING * 512


' ===============================
' MODULO: B+Tree Texto
' - Implementa uma B+Tree textual persistente
'
' DEPENDENCIAS:
' - Buffer
'
' ESTADO:
' - (nenhum)
' ===============================


CONST nChaves = 28
CONST tamPrefixo = 14
CONST tInterno = 1, tFolha = 2
CONST tamBloco = 512
CONST ponteiroNulo = 0
CONST tamCache = 16
CONST maxBPTrees = 5

TYPE CabecalhoGeral
  versao AS INTEGER
  posRaiz AS LONG
END TYPE

TYPE CabecalhoNoh
  tipo AS INTEGER
  qtdEntradas AS INTEGER
  ponteiroExtra AS LONG
END TYPE

TYPE EntradaNoh
  chave AS STRING * tamPrefixo
  ponteiro AS LONG
END TYPE

TYPE GerenciaCache
  inicioFila AS INTEGER
  finalFila AS INTEGER
END TYPE

TYPE InfoPromocao
  houvePromocao AS INTEGER
  chavePromovida AS STRING * tamPrefixo
  ponteiroOriginal AS LONG
  ponteiroNovo AS LONG
END TYPE

' TYPE...END TYPE precisa vir antes de qualquer DECLARE que o use (ver
' docs/armadilhas.md) - por isso os DECLAREs abaixo usam os tipos
' concretos (EntradaNoh/InfoPromocao) em vez do escape "AS ANY"
DECLARE SUB BPTreeTextoCriar (nArquivo%)
DECLARE SUB BPTreeTextoCarregar (nArquivo%)
DECLARE SUB BPTreeTextoInserir (nArquivo%, chave$, posArquivo&)
DECLARE SUB ModificarCabecalhoArquivo (nArquivo%, novaPosRaiz&)
DECLARE SUB CarregarNohBpttTexto (nArquivo%, idxCache%)
DECLARE SUB GravarNohBpttTexto (nArquivo%, idxCache%)
DECLARE SUB BpttInserirRecursivo (nArquivo%, idxCache%, chave$, posArquivo&, promocaoSubir AS InfoPromocao)
DECLARE FUNCTION BuscaNohNoCache% (nArquivo%, ponteiro&)
DECLARE SUB GravarEntradaNoNoh (nArquivo%, idxCache%, novaEntrada AS EntradaNoh, promocaoSubir AS InfoPromocao)
DECLARE FUNCTION AlocarEspacoCache% (nArquivo%, ponteiro&)
DECLARE FUNCTION ProximoBlocoLivre& (nArquivo%)
DECLARE FUNCTION CarregarNohNoCache% (nArquivo%, ponteiro&)
DECLARE SUB DivideNoh (nArquivo%, idxCacheOriginal%, promocaoSubir AS InfoPromocao)
DECLARE FUNCTION BuscarChaveTexto% (nArquivo%, idxCache%, chaveBuscada$)
DECLARE FUNCTION BPTreeTextoBuscar& (nArquivo%, chaveBuscada$)
DECLARE SUB VerificaCadeiaFolhas (nArquivo%, totalEsperado&)
DECLARE SUB VerificaAlinhamentoBlocos (nArquivo%, ponteiro&)
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
DECLARE SUB DumpNoh (nArquivo%, ponteiro&, profundidade%)

DIM SHARED bpttCabecalhoArquivo AS CabecalhoGeral

' CACHE DE NOHS
' Raiz: fixa
' 0..tamCache-1 fila circular
' Entradas: 0..nChaves-1 (+1 extra para tratar transbordo)
' Ponteiro da entrada
'   Nohs internos: eh o das chaves MENORES OU IGUAIS a chave na entrada
'   Folhas:        posicao da chave no arquivo de dados
' Ponteiro extra:
'   Nohs internos: eh o noh com as chaves MAIORES que a ultima
'   Folha: proxima folha (leitura sequencial)
CONST idxRaiz = -1
DIM SHARED bpttCabecalhos(1 TO maxBPTrees, idxRaiz TO tamCache - 1) AS CabecalhoNoh
DIM SHARED bpttEntradas(1 TO maxBPTrees, idxRaiz TO tamCache - 1, 0 TO nChaves) AS EntradaNoh
DIM SHARED bpttPonteiros(1 TO maxBPTrees, idxRaiz TO tamCache - 1) AS LONG
DIM SHARED bpttCache(1 TO maxBPTrees) AS GerenciaCache


' ================= TEST CODE start
' Harness auto-contido: gera suas proprias chaves (nao depende de
' amostra.csv/vendas.dat) - chaves numericas curtas (4 digitos), unicas,
' cabem inteiras no prefixo (tamPrefixo=14) sem truncar. Insere em ordem
' EMBARALHADA (nao crescente) pra exercitar split em posicoes variadas,
' nao so no fim do noh. N=1000 forca split de folha varias vezes E pelo
' menos 1 split da propria raiz (vira no interno, cria raiz nova).
CONST totalChaves = 1000

DIM SHARED totalFalhas AS INTEGER
DIM SHARED ultimaChaveInserida AS STRING, ultimaSeqInserida AS LONG
DIM SHARED totalNohsVerificados AS LONG, alinhamentoOk AS INTEGER
DIM ordemInsercao(1 TO totalChaves) AS LONG
DIM i AS LONG, j AS LONG, troca AS LONG
DIM chaveTeste AS STRING
DIM buscasOk AS LONG, buscasFalha AS LONG
DIM posEncontrada AS LONG

OPEN "BPTREE1.LOG" FOR OUTPUT AS #3
PRINT #3, "=== BPTREE1.BAS - insercao + split + persistencia + busca, N="; totalChaves; " ==="

ON ERROR GOTO TrataErro

tamanhoNoh% = LEN(bpttCabecalhos(1, 0)) + LEN(bpttEntradas(1, 0, 0)) * nChaves
PRINT #3, "Tamanho do noh (nChaves entradas): "; tamanhoNoh%; " bytes (tamBloco="; tamBloco; ")"
CALL Confere("noh cabe exatamente em tamBloco", "0", LTRIM$(STR$(tamBloco - tamanhoNoh%)))

' embaralha 1..totalChaves (Fisher-Yates, semente fixa pra reproduzir)
RANDOMIZE 42
FOR i = 1 TO totalChaves
  ordemInsercao(i) = i
NEXT i
FOR i = totalChaves TO 2 STEP -1
  j = INT(RND * i) + 1
  troca = ordemInsercao(i)
  ordemInsercao(i) = ordemInsercao(j)
  ordemInsercao(j) = troca
NEXT i

' garante arquivo novo - sem isso, um .IDX de uma rodada anterior fica maior
' que a arvore desta rodada, e LOF() (base do calculo de ProximoBlocoLivre&)
' partiria de um tamanho que nao corresponde aos blocos escritos agora.
' "ON ERROR RESUME NEXT" (uma unica instrucao) nao existe no QBasic - isso
' eh VB (ver docs/armadilhas.md). Idioma correto - RESUME explicito, fluxo
' de sucesso pula o handler via GOTO - ja usado em ARVDISCO.BAS/SISVALID.BAS
ON ERROR GOTO SemArquivoAntigo
KILL "BPTREE1.IDX"
GOTO ArquivoAntigoRemovido
SemArquivoAntigo:
RESUME ArquivoAntigoRemovido
ArquivoAntigoRemovido:
ON ERROR GOTO TrataErro

arqIndice% = FREEFILE
OPEN "BPTREE1.IDX" FOR BINARY AS arqIndice%
BPTreeTextoCriar arqIndice%

PRINT "Inserindo..."
FOR i = 1 TO totalChaves
  chaveTeste = RIGHT$("000" + LTRIM$(STR$(ordemInsercao(i))), 4)
  ultimaChaveInserida = chaveTeste
  ultimaSeqInserida = i
  BPTreeTextoInserir arqIndice%, chaveTeste, ordemInsercao(i)
  IF i MOD 100 = 0 THEN PRINT "."; ' so pra mostrar que esta vivo
NEXT i

CLOSE arqIndice%
PRINT #3, "Insercao concluida: "; totalChaves; " chaves"

' reabre do zero (sessao nova, memoria limpa) - valida persistencia,
' inclusive o cabecalho geral na posicao fixa 1
arqIndice% = FREEFILE
OPEN "BPTREE1.IDX" FOR BINARY AS arqIndice%
BPTreeTextoCarregar arqIndice%

PRINT
PRINT "Buscando..."
buscasOk = 0: buscasFalha = 0
FOR i = 1 TO totalChaves
  chaveTeste = RIGHT$("000" + LTRIM$(STR$(i)), 4)
  posEncontrada = BPTreeTextoBuscar&(arqIndice%, chaveTeste)
  IF posEncontrada = i THEN
    buscasOk = buscasOk + 1
  ELSE
    buscasFalha = buscasFalha + 1
    IF buscasFalha <= 20 THEN PRINT #3, "  falhou chave="; chaveTeste; " esperado="; i; " obtido="; posEncontrada
  END IF
  IF i MOD 100 = 0 THEN PRINT ".";
NEXT i
CALL Confere("buscas corretas = totalChaves", LTRIM$(STR$(totalChaves)), LTRIM$(STR$(buscasOk)))
CALL Confere("buscas com falha = 0", "0", LTRIM$(STR$(buscasFalha)))

posEncontrada = BPTreeTextoBuscar&(arqIndice%, "9999")
CALL Confere("busca chave inexistente devolve -1", "-1", LTRIM$(STR$(posEncontrada)))

' percurso independente pela cadeia de folhas (ponteiroExtra) - desce
' sempre pelo filho mais a esquerda ate a 1a folha, depois segue a
' cadeia. Confirma ordenacao e completude sem depender da logica de
' busca acima (verificacao estrutural, nao so round-trip)
CALL VerificaCadeiaFolhas(arqIndice%, totalChaves)

' verificacao direta do calculo de ProximoBlocoLivre&: percorre TODO noh
' (interno e folha) e confere que sua posicao no arquivo cai exatamente
' num limite de tamBloco. Sem isso, "0 falhas" nas buscas so prova
' ausencia de sintoma visivel, nao confirma o alinhamento em si
totalNohsVerificados = 0
alinhamentoOk = -1
CALL VerificaAlinhamentoBlocos(arqIndice%, bpttCabecalhoArquivo.posRaiz)
PRINT #3, "Nohs verificados (alinhamento): "; totalNohsVerificados
CALL Confere("todos os blocos alinhados a tamBloco", "-1", LTRIM$(STR$(alinhamentoOk)))

PRINT #3, ""
PRINT #3, "=== FIM. Falhas: "; totalFalhas; " ==="
CLOSE arqIndice%, #3

PRINT
PRINT "BPTREE1 OK. Falhas: "; totalFalhas; ". Ver BPTREE1.LOG"
SYSTEM

TrataErro:
PRINT #3, "*** ERRO EM RUNTIME (BPTREE1) *** ERR="; ERR; " ERL="; ERL; " ultimaChaveInserida="; ultimaChaveInserida; " seq="; ultimaSeqInserida
CLOSE #3
SYSTEM
' ================= TEST CODE end

' Aloca uma nova posição no cache, descarta a mais antiga se o cache esgotou
FUNCTION AlocarEspacoCache% (nArquivo%, ponteiro&)
  idxNovoNo% = bpttCache(nArquivo%).finalFila
  bpttCache(nArquivo%).finalFila = (bpttCache(nArquivo%).finalFila + 1) MOD tamCache

  IF bpttCache(nArquivo%).finalFila = bpttCache(nArquivo%).inicioFila THEN
    bpttCache(nArquivo%).inicioFila = (bpttCache(nArquivo%).inicioFila + 1) MOD tamCache
  END IF

  bpttPonteiros(nArquivo%, idxNovoNo%) = ponteiro&
  AlocarEspacoCache% = idxNovoNo%
END FUNCTION

' Calcula a posicao do proximo bloco livre a partir de LOF(), arredondando
' pra cima ate o proximo limite de tamBloco - sem contador separado (evitaria
' escrita extra no cabecalho, fora da posicao 1, a cada split) e sem
' "esticar" o arquivo artificialmente. So funciona porque o conteudo real de
' um noh nunca passa de tamBloco (nChaves entradas + cabecalho cabem
' exatamente nele, por construcao) - LOF() pode terminar NO MEIO de um
' bloco (gravamos so qtdEntradas, nao as nChaves todas), mas nunca alem dele
FUNCTION ProximoBlocoLivre& (nArquivo%)
  celula& = (LOF(nArquivo%) - 1) \ tamBloco
  ProximoBlocoLivre& = 1 + (celula& + 1) * tamBloco
END FUNCTION

' Carregamento de B+Tree inicializa cabeçalho e raiz com o que tem no arquivo
SUB BPTreeTextoCarregar (nArquivo%)
  GET nArquivo%, 1, bpttCabecalhoArquivo
  bpttPonteiros(nArquivo%, idxRaiz) = bpttCabecalhoArquivo.posRaiz
  CarregarNohBpttTexto nArquivo%, idxRaiz
  bpttCache(nArquivo%).inicioFila = 0
  bpttCache(nArquivo%).finalFila = 0
END SUB

' Criacao da B+Tree inicializa cabeçalho e raiz no arquivo e zera as estruturas de dados
SUB BPTreeTextoCriar (nArquivo%)
  SEEK nArquivo%, 1

  ' grava o cabecalho uma 1a vez (posRaiz provisorio) so pra LOF() refletir
  ' que a posicao 1 esta ocupada - ProximoBlocoLivre& usa LOF() pra calcular
  ' onde a raiz comeca, entao precisa de algo gravado antes
  ModificarCabecalhoArquivo nArquivo%, 0
  novaPosRaiz& = ProximoBlocoLivre&(nArquivo%)
  bpttPonteiros(nArquivo%, idxRaiz) = novaPosRaiz&
  ModificarCabecalhoArquivo nArquivo%, novaPosRaiz&

  bpttCabecalhos(nArquivo%, idxRaiz).tipo = tFolha
  bpttCabecalhos(nArquivo%, idxRaiz).qtdEntradas = 0
  bpttCabecalhos(nArquivo%, idxRaiz).ponteiroExtra = ponteiroNulo
  GravarNohBpttTexto nArquivo%, idxRaiz

  bpttCache(nArquivo%).inicioFila = 0
  bpttCache(nArquivo%).finalFila = 0
END SUB

' BpttInserirRecursivo(idxRaiz, ...) ja deixa idxRaiz totalmente
' atualizado quando volta - inclusive ja dividido (DivideNoh), se for o
' caso: raiz-como-folha insere e pode dividir direto (ramo ELSE de
' BpttInserirRecursivo); raiz-como-no-interno recebe a entrada promovida
' do filho e TAMBEM pode dividir (mesmo GravarEntradaNoNoh, chamado de
' dentro de BpttInserirRecursivo). Nos dois casos, promovidoDebaixo (o
' promocaoSubir de BpttInserirRecursivo) JA descreve o split da propria
' raiz, pronto pra usar - nao existe "entrada a mais" pra inserir aqui,
' so criar a raiz nova por cima quando promovidoDebaixo.houvePromocao<>0
SUB BPTreeTextoInserir (nArquivo%, chave$, posArquivo&)
  DIM promovidoDebaixo AS InfoPromocao
  BpttInserirRecursivo nArquivo%, idxRaiz, chave$, posArquivo&, promovidoDebaixo

  IF promovidoDebaixo.houvePromocao <> 0 THEN
    DIM promovido AS EntradaNoh
    promovido.chave = promovidoDebaixo.chavePromovida
    promovido.ponteiro = promovidoDebaixo.ponteiroOriginal
    novaPosRaiz& = ProximoBlocoLivre&(nArquivo%)
    ModificarCabecalhoArquivo nArquivo%, novaPosRaiz&
    bpttPonteiros(nArquivo%, idxRaiz) = novaPosRaiz&
    bpttCabecalhos(nArquivo%, idxRaiz).tipo = tInterno
    LSET bpttEntradas(nArquivo%, idxRaiz, 0) = promovido
    bpttCabecalhos(nArquivo%, idxRaiz).qtdEntradas = 1
    bpttCabecalhos(nArquivo%, idxRaiz).ponteiroExtra = promovidoDebaixo.ponteiroNovo
    GravarNohBpttTexto nArquivo%, idxRaiz
  END IF
END SUB

SUB BpttInserirRecursivo (nArquivo%, idxCache%, chave$, posArquivo&, promocaoSubir AS InfoPromocao)
  IF bpttCabecalhos(nArquivo%, idxCache%).tipo = tInterno THEN
    DIM promovidoDebaixo AS InfoPromocao
    DIM meuPonteiro AS LONG
    ' idxCache% eh um INDICE DE SLOT do cache, nao uma identidade estavel -
    ' o FIFO (AlocarEspacoCache%) pode reaproveitar esse slot pra outro noh
    ' enquanto a chamada recursiva abaixo ainda esta rodando (ele nao sabe
    ' que este slot esta "em uso" por uma chamada ainda nao retornada).
    ' Guarda a posicao em disco (essa sim estavel) pra reresolver depois.
    meuPonteiro = bpttPonteiros(nArquivo%, idxCache%)

    posChaveNoNoh% = BuscarChaveTexto%(nArquivo%, idxCache%, chave$)
    ' qtdEntradas deste noh especifico - BuscarChaveTexto% pode devolver ate
    ' esse valor (nao ate a constante nChaves), quando a chave eh maior que
    ' todas as entradas presentes
    qtdAtual% = bpttCabecalhos(nArquivo%, idxCache%).qtdEntradas

    IF posChaveNoNoh% = qtdAtual% THEN
      navegarPara& = bpttCabecalhos(nArquivo%, idxCache%).ponteiroExtra
    ELSE
      navegarPara& = bpttEntradas(nArquivo%, idxCache%, posChaveNoNoh%).ponteiro
    END IF

    posNoCache% = BuscaNohNoCache%(nArquivo%, navegarPara&)

    IF posNoCache% = -1 THEN
      posNoCache% = CarregarNohNoCache%(nArquivo%, navegarPara&)
    END IF

    BpttInserirRecursivo nArquivo%, posNoCache%, chave$, posArquivo&, promovidoDebaixo

    IF promovidoDebaixo.houvePromocao <> 0 THEN
      ' idxCache% pode ter sido reaproveitado durante a recursao acima -
      ' reresolve pelo ponteiro salvo (posChaveNoNoh%/qtdAtual% continuam
      ' validos, sao so valores, nao dependem de qual slot fisico usamos).
      ' EXCECAO: idxRaiz (-1) e fixo, nunca e evictado pelo FIFO - e
      ' tambem NAO aparece na busca de BuscaNohNoCache% (que so varre
      ' 0..tamCache-1). Reresolver quando idxCache%=idxRaiz carregaria
      ' uma SEGUNDA copia da raiz num slot comum, desconectada da copia
      ' de verdade em idxRaiz - dali em diante toda escrita cairia nessa
      ' copia orfa, nunca mais refletida na proxima insercao (que sempre
      ' comeca de novo em idxRaiz). Bug real, achado rodando com N=1000.
      IF idxCache% <> idxRaiz THEN
        idxCache% = BuscaNohNoCache%(nArquivo%, meuPonteiro)
        IF idxCache% = -1 THEN idxCache% = CarregarNohNoCache%(nArquivo%, meuPonteiro)
      END IF

      IF posChaveNoNoh% = qtdAtual% THEN
        bpttCabecalhos(nArquivo%, idxCache%).ponteiroExtra = promovidoDebaixo.ponteiroNovo
      ELSE
        bpttEntradas(nArquivo%, idxCache%, posChaveNoNoh%).ponteiro = promovidoDebaixo.ponteiroNovo
      END IF

      DIM promovido AS EntradaNoh
      promovido.chave = promovidoDebaixo.chavePromovida
      promovido.ponteiro = promovidoDebaixo.ponteiroOriginal

      GravarEntradaNoNoh nArquivo%, idxCache%, promovido, promocaoSubir
    END IF
  ELSE
    DIM novaEntrada AS EntradaNoh
    novaEntrada.chave = chave$
    novaEntrada.ponteiro = posArquivo&

    GravarEntradaNoNoh nArquivo%, idxCache%, novaEntrada, promocaoSubir
  END IF
END SUB

' Devolve o indice de um noh no cache dado seu ponteiro no arquivo; -1 caso nao esteja em memoria
FUNCTION BuscaNohNoCache% (nArquivo%, ponteiro&)
  FOR i% = 0 TO tamCache - 1
    IF bpttPonteiros(nArquivo%, i%) = ponteiro& THEN
      BuscaNohNoCache% = i%
      EXIT FUNCTION
    END IF
  NEXT

  BuscaNohNoCache% = -1
END FUNCTION

' Busca uma chave em um noh de B+Tree textual
FUNCTION BuscarChaveTexto% (nArquivo%, idxCache%, chaveBuscada$)
  esquerda% = -1
  direita% = bpttCabecalhos(nArquivo%, idxCache%).qtdEntradas

  DO WHILE esquerda% < direita% - 1
    meio% = (esquerda% + direita%) \ 2

    IF UCASE$(bpttEntradas(nArquivo%, idxCache%, meio%).chave) < UCASE$(chaveBuscada$) THEN
      esquerda% = meio%
    ELSE
      direita% = meio%
    END IF
  LOOP

  BuscarChaveTexto% = direita%
END FUNCTION

' Busca uma chave a partir da raiz, descendo pelo mesmo criterio de
' roteamento usado na insercao (BpttInserirRecursivo). Devolve o
' posArquivo& gravado com a chave, ou -1 se nao encontrada.
FUNCTION BPTreeTextoBuscar& (nArquivo%, chaveBuscada$)
  idxAtual% = idxRaiz

  DO WHILE bpttCabecalhos(nArquivo%, idxAtual%).tipo = tInterno
    posChaveNoNoh% = BuscarChaveTexto%(nArquivo%, idxAtual%, chaveBuscada$)
    qtdAtual% = bpttCabecalhos(nArquivo%, idxAtual%).qtdEntradas

    IF posChaveNoNoh% = qtdAtual% THEN
      navegarPara& = bpttCabecalhos(nArquivo%, idxAtual%).ponteiroExtra
    ELSE
      navegarPara& = bpttEntradas(nArquivo%, idxAtual%, posChaveNoNoh%).ponteiro
    END IF

    idxAtual% = BuscaNohNoCache%(nArquivo%, navegarPara&)
    IF idxAtual% = -1 THEN idxAtual% = CarregarNohNoCache%(nArquivo%, navegarPara&)
  LOOP

  ' idxAtual% agora eh uma folha
  posChaveNoNoh% = BuscarChaveTexto%(nArquivo%, idxAtual%, chaveBuscada$)
  qtdAtual% = bpttCabecalhos(nArquivo%, idxAtual%).qtdEntradas

  IF posChaveNoNoh% < qtdAtual% THEN
    ' RTRIM$ necessario: a chave armazenada eh STRING*tamPrefixo (com espaco
    ' de preenchimento a direita), chaveBuscada$ vem sem preenchimento
    IF UCASE$(RTRIM$(bpttEntradas(nArquivo%, idxAtual%, posChaveNoNoh%).chave)) = UCASE$(RTRIM$(chaveBuscada$)) THEN
      BPTreeTextoBuscar& = bpttEntradas(nArquivo%, idxAtual%, posChaveNoNoh%).ponteiro
      EXIT FUNCTION
    END IF
  END IF

  BPTreeTextoBuscar& = -1
END FUNCTION

' Carrega um noh do arquivo para a memória alocada no cache. Le so as
' qtdEntradas entradas em uso (nao as nChaves todas) - o espaco ALOCADO pro
' noh no arquivo continua fixo (tamBloco), mas o que de fato ocupa bytes
' varia; o "resto" do bloco fica como lixo intocado. A posicao do PROXIMO
' bloco livre nao depende de quanto este gravou - ve ProximoBlocoLivre&
SUB CarregarNohBpttTexto (nArquivo%, idxCache%)
  GET nArquivo%, bpttPonteiros(nArquivo%, idxCache%), bpttCabecalhos(nArquivo%, idxCache%)

  FOR i% = 0 TO bpttCabecalhos(nArquivo%, idxCache%).qtdEntradas - 1
    GET nArquivo%, , bpttEntradas(nArquivo%, idxCache%, i%)
  NEXT
END SUB

' Grava um noh do cache no arquivo - mesmo motivo acima: so as qtdEntradas em uso
SUB GravarNohBpttTexto (nArquivo%, idxCache%)
  PUT nArquivo%, bpttPonteiros(nArquivo%, idxCache%), bpttCabecalhos(nArquivo%, idxCache%)

  FOR i% = 0 TO bpttCabecalhos(nArquivo%, idxCache%).qtdEntradas - 1
    PUT nArquivo%, , bpttEntradas(nArquivo%, idxCache%, i%)
  NEXT
END SUB

' Le noh do arquivo para o cache
FUNCTION CarregarNohNoCache% (nArquivo%, ponteiro&)
  idxNovoNo% = AlocarEspacoCache%(nArquivo%, ponteiro&)
  GET nArquivo%, ponteiro&, BufferString
  CarregarNohBpttTexto nArquivo%, idxNovoNo%
  CarregarNohNoCache% = idxNovoNo%
END FUNCTION

' Split de noh
SUB DivideNoh (nArquivo%, idxCacheOriginal%, promocaoSubir AS InfoPromocao)
  ponteiroSplit& = ProximoBlocoLivre&(nArquivo%)
  meio% = nChaves \ 2

  promocaoSubir.houvePromocao = -1
  promocaoSubir.chavePromovida = bpttEntradas(nArquivo%, idxCacheOriginal%, meio%).chave
  promocaoSubir.ponteiroOriginal = bpttPonteiros(nArquivo%, idxCacheOriginal%)
  promocaoSubir.ponteiroNovo = ponteiroSplit&
  idxCacheNovo% = AlocarEspacoCache%(nArquivo%, ponteiroSplit&)

  ' a alocacao acima pode ter evictado o proprio idxCacheOriginal% (mesmo
  ' risco de BpttInserirRecursivo) - reresolve pelo ponteiro ja salvo.
  ' EXCECAO: idxRaiz (-1) e fixo, nunca evictado, e nao aparece na busca
  ' de BuscaNohNoCache% (so varre 0..tamCache-1) - reresolver quando
  ' idxCacheOriginal%=idxRaiz carregaria uma SEGUNDA copia orfa da raiz
  IF idxCacheOriginal% <> idxRaiz THEN
    idxCacheOriginal% = BuscaNohNoCache%(nArquivo%, promocaoSubir.ponteiroOriginal)
    IF idxCacheOriginal% = -1 THEN idxCacheOriginal% = CarregarNohNoCache%(nArquivo%, promocaoSubir.ponteiroOriginal)
  END IF

  cont% = 0
  FOR i% = meio% + 1 TO nChaves
    LSET bpttEntradas(nArquivo%, idxCacheNovo%, cont%) = bpttEntradas(nArquivo%, idxCacheOriginal%, i%)
    cont% = cont% + 1
  NEXT

  bpttPonteiros(nArquivo%, idxCacheNovo%) = ponteiroSplit&
  bpttCabecalhos(nArquivo%, idxCacheNovo%).tipo = bpttCabecalhos(nArquivo%, idxCacheOriginal%).tipo
  bpttCabecalhos(nArquivo%, idxCacheNovo%).qtdEntradas = meio%
  bpttCabecalhos(nArquivo%, idxCacheNovo%).ponteiroExtra = bpttCabecalhos(nArquivo%, idxCacheOriginal%).ponteiroExtra

  IF bpttCabecalhos(nArquivo%, idxCacheOriginal%).tipo = tInterno THEN
    ' desnecessario, consequencia da convencao do ponteiro do noh apontar para chaves <= a chave do noh
    bpttCabecalhos(nArquivo%, idxCacheOriginal%).ponteiroExtra = 0
  ELSE
    ' ligacao sequencial
    bpttCabecalhos(nArquivo%, idxCacheOriginal%).ponteiroExtra = ponteiroSplit&
  END IF

  bpttCabecalhos(nArquivo%, idxCacheOriginal%).qtdEntradas = meio% + 1

  GravarNohBpttTexto nArquivo%, idxCacheOriginal%
  GravarNohBpttTexto nArquivo%, idxCacheNovo%
END SUB

' Grava uma entrada em um noh e informa se foi necessario split, qual noh foi promovido e o ponteiro para o novo noh criado
SUB GravarEntradaNoNoh (nArquivo%, idxCache%, novaEntrada AS EntradaNoh, promocaoSubir AS InfoPromocao)
  posChaveNoNoh% = BuscarChaveTexto%(nArquivo%, idxCache%, novaEntrada.chave)
  qtdEntradas% = bpttCabecalhos(nArquivo%, idxCache%).qtdEntradas

  FOR i% = qtdEntradas% - 1 TO posChaveNoNoh% STEP -1
    LSET bpttEntradas(nArquivo%, idxCache%, i% + 1) = bpttEntradas(nArquivo%, idxCache%, i%)
  NEXT

  ' faltava: a entrada nova em si nunca era escrita no slot aberto pelo deslocamento acima
  LSET bpttEntradas(nArquivo%, idxCache%, posChaveNoNoh%) = novaEntrada

  ' gatilho de split: qtdEntradas% eh a contagem ANTES desta insercao - se o noh
  ' ja estava cheio (nChaves), a entrada nova coube so no slot extra de transbordo
  ' (indice nChaves, dimensionado a parte pra isso) e precisa dividir
  IF qtdEntradas% = nChaves THEN
    DivideNoh nArquivo%, idxCache%, promocaoSubir
  ELSE
    promocaoSubir.houvePromocao = 0
    bpttCabecalhos(nArquivo%, idxCache%).qtdEntradas = qtdEntradas% + 1
    GravarNohBpttTexto nArquivo%, idxCache%
  END IF
END SUB

' Modificamos o cabecalho do arquivo na criacao de nova B+Tree ou quando uma nova raiz e criada
SUB ModificarCabecalhoArquivo (nArquivo%, novaPosRaiz&)
  bpttCabecalhoArquivo.versao = 1
  bpttCabecalhoArquivo.posRaiz = novaPosRaiz&
  PUT nArquivo%, 1, bpttCabecalhoArquivo
END SUB

' Percorre a cadeia de folhas (ponteiroExtra) do inicio ao fim, sem
' depender de BPTreeTextoBuscar& - desce sempre pelo filho MAIS A
' ESQUERDA a partir da raiz ate achar a 1a folha, depois segue a cadeia.
' Confirma ordenacao estritamente crescente e contagem total.
SUB VerificaCadeiaFolhas (nArquivo%, totalEsperado&)
  DIM chaveAnterior AS STRING, chaveAtual AS STRING
  DIM qtdVisitadas AS LONG, ordemOk AS INTEGER
  DIM ponteiroFolha AS LONG, idxAtual AS INTEGER, i AS INTEGER

  idxAtual = idxRaiz
  DO WHILE bpttCabecalhos(nArquivo%, idxAtual).tipo = tInterno
    ponteiroFolha = bpttEntradas(nArquivo%, idxAtual, 0).ponteiro
    idxAtual = BuscaNohNoCache%(nArquivo%, ponteiroFolha)
    IF idxAtual = -1 THEN idxAtual = CarregarNohNoCache%(nArquivo%, ponteiroFolha)
  LOOP

  qtdVisitadas = 0
  ordemOk = -1
  chaveAnterior = ""

  DO
    FOR i = 0 TO bpttCabecalhos(nArquivo%, idxAtual).qtdEntradas - 1
      chaveAtual = RTRIM$(bpttEntradas(nArquivo%, idxAtual, i).chave)
      IF chaveAnterior <> "" THEN
        IF UCASE$(chaveAtual) <= UCASE$(chaveAnterior) THEN ordemOk = 0
      END IF
      chaveAnterior = chaveAtual
      qtdVisitadas = qtdVisitadas + 1
    NEXT i

    ponteiroFolha = bpttCabecalhos(nArquivo%, idxAtual).ponteiroExtra
    IF ponteiroFolha = ponteiroNulo THEN EXIT DO
    idxAtual = BuscaNohNoCache%(nArquivo%, ponteiroFolha)
    IF idxAtual = -1 THEN idxAtual = CarregarNohNoCache%(nArquivo%, ponteiroFolha)
  LOOP

  CALL Confere("cadeia de folhas: visitou totalChaves registros", LTRIM$(STR$(totalEsperado&)), LTRIM$(STR$(qtdVisitadas)))
  CALL Confere("cadeia de folhas: ordem estritamente crescente", "-1", LTRIM$(STR$(ordemOk)))
END SUB

' Assert simples: grava OK/FALHA no log e conta falhas
SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
  IF esperado = obtido THEN
    PRINT #3, "OK    - "; descricao
  ELSE
    PRINT #3, "FALHA - "; descricao; " | esperado=["; esperado; "] obtido=["; obtido; "]"
    totalFalhas = totalFalhas + 1
  END IF
END SUB

' Percorre TODO noh da arvore (interno e folha) e confere que sua posicao
' cai exatamente num limite de tamBloco - verificacao direta do calculo de
' ProximoBlocoLivre&, nao so ausencia de sintoma indireto (busca/cadeia OK
' tambem ficariam OK por acidente se um desalinhamento nao corrompesse
' nada visivel). Mesma captura-antes-de-recursar do DumpNoh abaixo.
SUB VerificaAlinhamentoBlocos (nArquivo%, ponteiro&)
  DIM idxC%, k%
  DIM tipoNoh%, qtdNoh%, ponteiroExtraNoh AS LONG
  DIM filhoPonteiro(0 TO 27) AS LONG

  IF (ponteiro& - 1) MOD tamBloco <> 0 THEN alinhamentoOk = 0
  totalNohsVerificados = totalNohsVerificados + 1

  idxC% = BuscaNohNoCache%(nArquivo%, ponteiro&)
  IF idxC% = -1 THEN idxC% = CarregarNohNoCache%(nArquivo%, ponteiro&)

  tipoNoh% = bpttCabecalhos(nArquivo%, idxC%).tipo
  qtdNoh% = bpttCabecalhos(nArquivo%, idxC%).qtdEntradas
  ponteiroExtraNoh = bpttCabecalhos(nArquivo%, idxC%).ponteiroExtra

  IF tipoNoh% = tInterno THEN
    FOR k% = 0 TO qtdNoh% - 1
      filhoPonteiro(k%) = bpttEntradas(nArquivo%, idxC%, k%).ponteiro
    NEXT k%
    FOR k% = 0 TO qtdNoh% - 1
      VerificaAlinhamentoBlocos nArquivo%, filhoPonteiro(k%)
    NEXT k%
    IF ponteiroExtraNoh <> 0 THEN
      VerificaAlinhamentoBlocos nArquivo%, ponteiroExtraNoh
    END IF
  END IF
END SUB

' Dump recursivo da arvore (diagnostico/inspecao manual - nao chamado
' pelo harness principal). Captura tudo em variaveis locais ANTES de
' recursar - idxC% (indice de slot) nao sobrevive de forma confiavel a
' uma chamada recursiva (mesmo risco de eviccao do
' BpttInserirRecursivo/DivideNoh, mas aqui e so leitura: sem essa
' captura o dump reportaria lixo, nao corromperia o arquivo)
SUB DumpNoh (nArquivo%, ponteiro&, profundidade%)
  DIM idxC%, k%, prefixo$
  DIM tipoNoh%, qtdNoh%, ponteiroExtraNoh AS LONG
  DIM filhoPonteiro(0 TO 27) AS LONG

  idxC% = BuscaNohNoCache%(nArquivo%, ponteiro&)
  IF idxC% = -1 THEN idxC% = CarregarNohNoCache%(nArquivo%, ponteiro&)

  tipoNoh% = bpttCabecalhos(nArquivo%, idxC%).tipo
  qtdNoh% = bpttCabecalhos(nArquivo%, idxC%).qtdEntradas
  ponteiroExtraNoh = bpttCabecalhos(nArquivo%, idxC%).ponteiroExtra

  prefixo$ = STRING$(profundidade% * 2, "-")
  PRINT #3, prefixo$; "noh@"; ponteiro&; " tipo="; tipoNoh%; " qtd="; qtdNoh%; " ponteiroExtra="; ponteiroExtraNoh

  FOR k% = 0 TO qtdNoh% - 1
    filhoPonteiro(k%) = bpttEntradas(nArquivo%, idxC%, k%).ponteiro
    PRINT #3, prefixo$; "  ["; k%; "] chave="; RTRIM$(bpttEntradas(nArquivo%, idxC%, k%).chave); " ponteiro="; filhoPonteiro(k%)
  NEXT k%

  IF tipoNoh% = tInterno THEN
    FOR k% = 0 TO qtdNoh% - 1
      DumpNoh nArquivo%, filhoPonteiro(k%), profundidade% + 1
    NEXT k%
    IF ponteiroExtraNoh <> 0 THEN
      DumpNoh nArquivo%, ponteiroExtraNoh, profundidade% + 1
    END IF
  END IF
END SUB
