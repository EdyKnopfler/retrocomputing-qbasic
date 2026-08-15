' CHAINB1.BAS - segunda ponta do teste de CHAINA1.BAS: confere se os
' dados sobrevivem ao CHAIN SEM re-REDIMensionar o array dinamico
' COMMON SHARED. Ver docs/decisoes.md.

COMMON SHARED vals() AS LONG
COMMON SHARED jaRedimensionado AS INTEGER

OPEN "CHAINOUT.TXT" FOR OUTPUT AS #1
PRINT #1, "jaRedimensionado (deveria ser -1, veio de CHAINA1): "; jaRedimensionado
PRINT #1, "vals(1) sem re-REDIM (deveria ser 111): "; vals(1)
PRINT #1, "vals(2) sem re-REDIM (deveria ser 222): "; vals(2)
PRINT #1, "vals(3) sem re-REDIM (deveria ser 333): "; vals(3)
CLOSE #1
SYSTEM
