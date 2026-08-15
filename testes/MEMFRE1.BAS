' MEMFRE1.BAS - mede FRE(-1)/FRE(-2)/FRE("") com a mesma estatica de
' SISTEMA.BAS EXCETO os arrays de cache do topo da arvore - mede o teto
' disponivel ANTES de aloca-los, pra decidir a capacidade com base em
' numero real, nao teorico. Ver docs/decisoes.md.

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

DIM SHARED noDiscoCliente AS NoClientePrimario
DIM SHARED noDiscoProduto AS NoProdutoPrimario
DIM opcao AS STRING

OPEN "MEMOUT1.TXT" FOR OUTPUT AS #1
PRINT #1, FRE(-1)
PRINT #1, FRE(-2)
PRINT #1, FRE("")
CLOSE #1
SYSTEM
