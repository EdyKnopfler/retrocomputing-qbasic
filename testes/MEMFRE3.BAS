' MEMFRE3.BAS - acha o teto REAL (empirico) de capacidade de cache de
' produto via REDIM em busca binaria, com ON ERROR pra nao travar em
' dialogo modal de "Out of memory". Replica a estatica completa de
' SISTEMA.BAS (TYPE, cliente fixo em 500, contadores COMMON) e so o
' array de produto vira dinamico pra poder tentar varios tamanhos no
' mesmo processo. Ver docs/decisoes.md.

CONST RRNPRIMEIRONO& = 1
CONST capacidadeCacheCliente% = 500
CONST RRNULTIMOCACHECliente& = RRNPRIMEIRONO& + capacidadeCacheCliente% - 1

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

DIM cacheClienteChave(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS STRING * 11
DIM cacheClienteEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG
DIM cacheClienteDir(RRNPRIMEIRONO& TO RRNULTIMOCACHECliente&) AS LONG

COMMON SHARED cacheProdutoChave() AS STRING * 13
COMMON SHARED cacheProdutoEsq() AS LONG
COMMON SHARED cacheProdutoDir() AS LONG

DIM SHARED noDiscoCliente AS NoClientePrimario
DIM SHARED noDiscoProduto AS NoProdutoPrimario

DIM lo AS LONG, hi AS LONG, meio AS LONG, resultado AS LONG, falhouEste AS INTEGER

OPEN "MEMOUT3.TXT" FOR OUTPUT AS #9

lo = 1
hi = 5041
resultado = 0

DO WHILE lo <= hi
  meio = (lo + hi) \ 2
  falhouEste = 0

  ON ERROR GOTO TrataErro
  REDIM cacheProdutoChave(RRNPRIMEIRONO& TO RRNPRIMEIRONO& + meio - 1) AS STRING * 13
  REDIM cacheProdutoEsq(RRNPRIMEIRONO& TO RRNPRIMEIRONO& + meio - 1) AS LONG
  REDIM cacheProdutoDir(RRNPRIMEIRONO& TO RRNPRIMEIRONO& + meio - 1) AS LONG
  ON ERROR GOTO 0
  GOTO SemErro

TrataErro:
  falhouEste = 1
  RESUME SemErro

SemErro:
  IF falhouEste THEN
    PRINT #9, "FALHA "; meio
    hi = meio - 1
  ELSE
    PRINT #9, "OK    "; meio; " FRE(-1)="; FRE(-1)
    resultado = meio
    lo = meio + 1
  END IF
LOOP

PRINT #9, "TETO REAL capacidadeCacheProduto%: "; resultado
CLOSE #9
SYSTEM

