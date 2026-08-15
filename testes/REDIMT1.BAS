' REDIMT1.BAS - testa REDIM em array dinamico (COMMON SHARED sem bounds),
' e se a alocacao dinamica sai do mesmo orcamento estatico medido por
' FRE(-1) ou de um pool separado. Ver docs/decisoes.md.

COMMON SHARED scores() AS INTEGER

DIM n AS INTEGER

OPEN "REDOUT1.TXT" FOR OUTPUT AS #1
PRINT #1, "FRE(-1) antes de qualquer REDIM: "; FRE(-1)

n = 5
REDIM scores(1 TO n) AS INTEGER
PRINT #1, "REDIM scores(1 TO n) com n=5 (variavel, nao literal): OK"
PRINT #1, "FRE(-1) depois REDIM pequeno (5 elementos): "; FRE(-1)

n = 20000
REDIM scores(1 TO n) AS INTEGER
PRINT #1, "REDIM scores(1 TO n) com n=20000 (40000 bytes se fosse estatico): OK"
PRINT #1, "FRE(-1) depois REDIM grande (20000 elementos): "; FRE(-1)

CLOSE #1
SYSTEM
