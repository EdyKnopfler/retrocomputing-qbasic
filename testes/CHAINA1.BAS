' CHAINA1.BAS - testa se REDIM em array dinamico COMMON SHARED sobrevive
' a um CHAIN, e se o modulo destino precisa (ou nao) re-REDIMensionar
' pra poder usar o array. Ver docs/decisoes.md.

COMMON SHARED vals() AS LONG
COMMON SHARED jaRedimensionado AS INTEGER

REDIM vals(1 TO 5) AS LONG
vals(1) = 111
vals(2) = 222
vals(3) = 333
jaRedimensionado = -1

CHAIN "CHAINB1.BAS"
