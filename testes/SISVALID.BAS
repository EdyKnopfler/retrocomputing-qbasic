' SISVALID.BAS - copia instrumentada de SISTEMA.BAS so para validar em
' QBASIC.EXE de verdade (harness headless, sem bloquear em INPUT).
' Descartavel, nao e arquivo de producao. Ver docs/plano-de-trabalho.md.
'
' Objetivo do teste: confirmar se um DIM re-executado (CHAIN reinicia o
' programa do topo) apaga o conteudo de um array/TYPE que veio via
' COMMON SHARED, e se reabrir CLIENTE.IDX/PRODUTO.IDX como #1/#2 (ja
' abertos, nunca fechados) da erro "file already open".

DECLARE SUB AbreIndiceCliente ()
DECLARE SUB AbreIndiceProduto ()

CONST tamChaveCliente% = 11
CONST tamChaveProduto% = 13
CONST RRNHEADER& = 1
CONST RRNPRIMEIRONO& = 2

CONST capacidadeCacheCliente% = 50
CONST capacidadeCacheProduto% = 100

CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1
CONST RRNULTIMOCACHEProduto& = RRNPRIMEIRONO& + capacidadeCacheProduto% - 1

TYPE NoClientePrimario
  chave AS STRING * 11
  esquerda AS LONG
  direita AS LONG
  excluido AS INTEGER
END TYPE

TYPE NoProdutoPrimario
  chave AS STRING * 13
  esquerda AS LONG
  direita AS LONG
  excluido AS INTEGER
END TYPE

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

DIM SHARED noDiscoCliente AS NoClientePrimario
DIM SHARED noDiscoProduto AS NoProdutoPrimario
DIM SHARED existeClienteIdx AS INTEGER
DIM SHARED existeProdutoIdx AS INTEGER
DIM passo AS STRING

OPEN "VALID.LOG" FOR APPEND AS #7
PRINT #7, "--- SISVALID: entrada. indicesCarregados="; indicesCarregados

ON ERROR GOTO TrataErro

PRINT #7, "Antes do IF: cabecalhoCliente.qtdInseridos="; cabecalhoCliente.qtdInseridos; " raizRRN="; cabecalhoCliente.raizRRN; " cacheClienteChave(2)=["; cacheClienteChave(2); "]"

IF indicesCarregados = 0 THEN
  PRINT #7, "indicesCarregados=0 -> vai chamar AbreIndice*"

  existeClienteIdx = -1
  ON ERROR GOTO NaoExisteCliente
  OPEN "CLIENTE.IDX" FOR INPUT AS #9
  CLOSE #9
  GOTO VerificouCliente
NaoExisteCliente:
  existeClienteIdx = 0
  RESUME VerificouCliente
VerificouCliente:
  ON ERROR GOTO TrataErro

  existeProdutoIdx = -1
  ON ERROR GOTO NaoExisteProduto
  OPEN "PRODUTO.IDX" FOR INPUT AS #9
  CLOSE #9
  GOTO VerificouProduto
NaoExisteProduto:
  existeProdutoIdx = 0
  RESUME VerificouProduto
VerificouProduto:
  ON ERROR GOTO TrataErro

  CALL AbreIndiceCliente
  CALL AbreIndiceProduto
  indicesCarregados = -1

  PRINT #7, "AbreIndice* OK. qtdInseridos="; cabecalhoCliente.qtdInseridos

  ' Sentinela: mutar estado pra provar, na volta do CHAIN, se sobreviveu
  ' ao re-DIM do topo deste mesmo programa.
  cabecalhoCliente.qtdInseridos = 999
  cabecalhoCliente.raizRRN = 12345
  cacheClienteChave(2) = "SENTINELA999"

  PRINT #7, "Sentinela gravada. Indo para CLIVALID.BAS (simula opcao 1)"
  CLOSE #7
  CHAIN "CLIVALID.BAS"
ELSE
  PRINT #7, "indicesCarregados<>0 -> pulou AbreIndice* (retorno de CHAIN)"
  PRINT #7, "Depois do retorno: qtdInseridos="; cabecalhoCliente.qtdInseridos; " raizRRN="; cabecalhoCliente.raizRRN; " cacheClienteChave(2)=["; cacheClienteChave(2); "]"
  IF cabecalhoCliente.qtdInseridos = 999 AND cacheClienteChave(2) = "SENTINELA99" THEN
    PRINT #7, "RESULTADO: sentinela sobreviveu ao CHAIN de ida e volta + re-DIM. OK."
  ELSE
    PRINT #7, "RESULTADO: sentinela NAO sobreviveu. re-DIM apaga dado do COMMON. PRECISA MUDAR DESENHO."
  END IF
  PRINT #7, "--- SISVALID: fim ---"
  CLOSE #1, #2, #7
  SYSTEM
END IF

END

TrataErro:
PRINT #7, "*** ERRO EM RUNTIME (SISVALID) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM

SUB AbreIndiceCliente
  DIM r AS LONG

  OPEN "CLIENTE.IDX" FOR RANDOM AS #1 LEN = LEN(noDiscoCliente)

  IF existeClienteIdx = 0 THEN
    cabecalhoCliente.proxRRNLivre = RRNPRIMEIRONO& - 1
    cabecalhoCliente.raizRRN = 0
    cabecalhoCliente.qtdExcluidos = 0
    cabecalhoCliente.qtdInseridos = 0
    PUT #1, RRNHEADER&, cabecalhoCliente
  ELSE
    GET #1, RRNHEADER&, cabecalhoCliente
  END IF

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&
    GET #1, r, noDiscoCliente
    cacheClienteChave(r) = noDiscoCliente.chave
    cacheClienteEsq(r) = noDiscoCliente.esquerda
    cacheClienteDir(r) = noDiscoCliente.direita
  NEXT r
END SUB

SUB AbreIndiceProduto
  DIM r AS LONG

  OPEN "PRODUTO.IDX" FOR RANDOM AS #2 LEN = LEN(noDiscoProduto)

  IF existeProdutoIdx = 0 THEN
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
