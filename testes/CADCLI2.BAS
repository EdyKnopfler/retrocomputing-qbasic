' CADCLI2.BAS - FASE 2
' Continuacao de CADCLI1.BAS. Roda como processo QBASIC.EXE SEPARADO
' (sem CHAIN, sem COMMON - memoria zerada de verdade), sobre o MESMO
' CLIENTE.DAT deixado pela fase 1 (nao apagar entre as duas execucoes).
'
' Objetivo especifico desta fase: provar que AbreArquivo reconstroi o
' topo da arvore (cache SoA) e os contadores (proxRRNLivre/qtdInseridos/
' qtdExcluidos) so a partir de LOF(1) + leitura dos registros - sem
' nenhum registro de cabecalho e sem nenhum estado herdado da fase 1 - e
' que Busca/InsereOuReativa continuam corretos em cima desse reload.
' Fase 1 so prova insercao em arquivo vazio dentro de um processo
' continuo; nao prova reload.
'
' Ver CADCLI1.BAS para contexto completo (indice primario autoindexado
' por CPF, campos de negocio, decisao de nao ter registro de cabecalho -
' raiz e sempre RRN 1, ver docs/decisoes.md).

TYPE NoCliente                    ' 11+50+16+80+80+9+30+2+4+4+2 = 288 bytes/registro
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
  excluido    AS INTEGER          ' 0 = ativo, 1 = removido (logico, no fica na arvore)
END TYPE

DECLARE SUB AbreArquivo ()
DECLARE SUB LeNoNav (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
DECLARE SUB CarregaRegistro (rrn AS LONG, reg AS NoCliente)
DECLARE SUB GravaRegistro (rrn AS LONG, reg AS NoCliente)
DECLARE SUB Busca (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
DECLARE SUB InsereOuReativa (reg AS NoCliente, sucesso AS INTEGER, reativado AS INTEGER)
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
DECLARE FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)

CONST RRNPRIMEIRONO& = 1          ' tambem e SEMPRE o RRN da raiz - ver CADCLI1.BAS
CONST capacidadeCache% = 500      ' clientes cabem inteiros em RAM com folga (docs/arquitetura-tecnica.md)
CONST RRNULTIMOCACHE& = RRNPRIMEIRONO& + capacidadeCache% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

DIM SHARED cacheCpf(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS STRING * 11
DIM SHARED cacheEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG
DIM SHARED cacheDir(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG

DIM SHARED regDisco AS NoCliente
DIM SHARED proxRRNLivre AS LONG   ' recalculado de LOF neste AbreArquivo - nada herdado da fase 1
DIM SHARED qtdInseridos AS LONG
DIM SHARED qtdExcluidos AS LONG
DIM SHARED totalFalhas AS INTEGER

' ---------------------------------------------------------------------
' Harness de teste - FASE 2: reload do CLIENTE.DAT da fase 1, processo novo
' ---------------------------------------------------------------------

DIM reg AS NoCliente
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM sucesso AS INTEGER, reativado AS INTEGER
DIM rrnCliente3 AS LONG

OPEN "CLIENTE.LOG" FOR APPEND AS #7
PRINT #7, ""
PRINT #7, "=== CADCLI2.BAS (FASE 2) - reload de CLIENTE.DAT, processo novo ==="

ON ERROR GOTO TrataErro

CALL AbreArquivo   ' aqui e onde o topo da arvore e os contadores voltam so via LOF + GET

CALL Confere("reload: LOF(1)\LEN(registro) = 3 (fase 1 deixou 3 registros)", "3", LTRIM$(STR$(LOF(1) \ LEN(regDisco))))
CALL Confere("reload: proxRRNLivre = 3", "3", LTRIM$(STR$(proxRRNLivre)))
CALL Confere("reload: qtdInseridos = 3", "3", LTRIM$(STR$(qtdInseridos)))
CALL Confere("reload: qtdExcluidos = 1", "1", LTRIM$(STR$(qtdExcluidos)))

' --- busca clientes inseridos na fase 1, usando SO o cache reconstruido do disco ---
CALL Busca(ChaveFixaCPF$("11111111111"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reload: acha cliente 1 (11111111111)", "-1", LTRIM$(STR$(achou)))
CALL Confere("reload: cliente 1 continua na raiz (RRN 1)", "1", LTRIM$(STR$(rrnAch)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("reload: nome do cliente 1 bate", "Maria Silva", RTRIM$(reg.nome))
CALL Confere("reload: endereco do cliente 1 bate", "Rua A, 100", RTRIM$(reg.endereco))

CALL Busca(ChaveFixaCPF$("22222222222"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reload: acha cliente 2 (22222222222)", "-1", LTRIM$(STR$(achou)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("reload: nome do cliente 2 bate", "Joao Souza", RTRIM$(reg.nome))

' --- cliente 3 foi marcado removido na fase 1: confere que sobreviveu ao reload ---
CALL Busca(ChaveFixaCPF$("33333333333"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reload: ainda acha o no do cliente 3 (removido)", "-1", LTRIM$(STR$(achou)))
rrnCliente3 = rrnAch
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("reload: excluido=1 do cliente 3 sobreviveu", "1", LTRIM$(STR$(reg.excluido)))

' --- reinsere o CPF removido, agora em cima de estado 100% vindo do disco ---
reg.cpf = ChaveFixaCPF$("33333333333")
reg.nome = "Ana Costa Silva"
reg.telefone = "31966665555"
reg.endereco = "Rua C, 300"
reg.complemento = "Casa"
reg.cep = "30000-000"
reg.cidade = "Belo Horizonte"
reg.uf = "MG"
CALL InsereOuReativa(reg, sucesso, reativado)
CALL Confere("reativa cliente 3 apos reload", "-1,-1", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

CALL Busca(ChaveFixaCPF$("33333333333"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("reativacao reaproveita o mesmo RRN de antes do reload", LTRIM$(STR$(rrnCliente3)), LTRIM$(STR$(rrnAch)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("nome atualizado apos reativacao", "Ana Costa Silva", RTRIM$(reg.nome))
CALL Confere("excluido=0 apos reativacao", "0", LTRIM$(STR$(reg.excluido)))
CALL Confere("cache reflete CPF apos reativacao", ChaveFixaCPF$("33333333333"), cacheCpf(rrnCliente3))

' --- contadores finais ---
CALL Confere("qtdInseridos final = 3 (reativacao nao conta insercao)", "3", LTRIM$(STR$(qtdInseridos)))
CALL Confere("qtdExcluidos final = 0", "0", LTRIM$(STR$(qtdExcluidos)))
CALL Confere("LOF(1)\LEN(registro) final = 3 (reativacao nao aloca registro novo)", "3", LTRIM$(STR$(LOF(1) \ LEN(regDisco))))

PRINT #7, ""
PRINT #7, "=== FIM FASE 2. Falhas: "; totalFalhas; " ==="
CLOSE #1, #7

PRINT "FASE 2 OK. Falhas: "; totalFalhas; ". Ver CLIENTE.LOG"
SYSTEM

TrataErro:
PRINT #7, "*** ERRO EM RUNTIME (CADCLI2) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM

' ---------------------------------------------------------------------
' REPETICAO: suporte de indice primario autoindexado por CPF - copia
' identica em CADCLI1.BAS (sem $INCLUDE, cada fase e um processo
' QBASIC.EXE a parte). Ver docs/convencoes.md sobre duplicacao aceita.
' (MarcaRemovido nao e usada nesta fase, por isso nao esta copiada aqui.)
' ---------------------------------------------------------------------

' Normaliza CPF pra chave fixa de 11 digitos (zeros a esquerda)
FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
  ChaveFixaCPF$ = RIGHT$("00000000000" + cpfBruto, 11)
END FUNCTION

' Abre CLIENTE.DAT (ja existe, deixado pela fase 1). Deriva
' proxRRNLivre/qtdInseridos de LOF (sem registro de cabecalho) e espelha
' campos magros de navegacao pro cache SoA, tabulando qtdExcluidos no
' mesmo passe.
SUB AbreArquivo
  DIM r AS LONG, totalRegistros AS LONG

  OPEN "CLIENTE.DAT" FOR RANDOM AS #1 LEN = LEN(regDisco)

  totalRegistros = LOF(1) \ LEN(regDisco)
  proxRRNLivre = totalRegistros
  qtdInseridos = totalRegistros
  qtdExcluidos = 0

  FOR r = RRNPRIMEIRONO& TO RRNULTIMOCACHE&
    IF r > totalRegistros THEN EXIT FOR   ' alocacao densa - resto do arquivo nao existe
    GET #1, r, regDisco
    cacheCpf(r) = regDisco.cpf
    cacheEsq(r) = regDisco.esquerda
    cacheDir(r) = regDisco.direita
    IF regDisco.excluido = 1 THEN qtdExcluidos = qtdExcluidos + 1
  NEXT r

  IF totalRegistros > RRNULTIMOCACHE& THEN
    FOR r = RRNULTIMOCACHE& + 1 TO totalRegistros
      GET #1, r, regDisco
      IF regDisco.excluido = 1 THEN qtdExcluidos = qtdExcluidos + 1
    NEXT r
  END IF
END SUB

' Le so os campos de navegacao de um no: do cache SoA se o RRN estiver
' na faixa, senao do arquivo
SUB LeNoNav (rrn AS LONG, cpf AS STRING, esq AS LONG, dir AS LONG)
  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHE& THEN
    cpf = cacheCpf(rrn)
    esq = cacheEsq(rrn)
    dir = cacheDir(rrn)
  ELSE
    GET #1, rrn, regDisco
    cpf = regDisco.cpf
    esq = regDisco.esquerda
    dir = regDisco.direita
  END IF
END SUB

' Le o registro completo direto do arquivo
SUB CarregaRegistro (rrn AS LONG, reg AS NoCliente)
  GET #1, rrn, reg
END SUB

' Grava um registro completo: sempre no arquivo; write-through no cache
' (so campos de navegacao) se o RRN estiver na faixa cacheada
SUB GravaRegistro (rrn AS LONG, reg AS NoCliente)
  PUT #1, rrn, reg

  IF rrn >= RRNPRIMEIRONO& AND rrn <= RRNULTIMOCACHE& THEN
    cacheCpf(rrn) = reg.cpf
    cacheEsq(rrn) = reg.esquerda
    cacheDir(rrn) = reg.direita
  END IF
END SUB

' Busca por CPF, a partir da raiz (SEMPRE RRN 1)
SUB Busca (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
  DIM rrnAtual AS LONG, rrnPaiAtual AS LONG, lado AS INTEGER
  DIM cpfAtual AS STRING, esq AS LONG, dir AS LONG

  achou = 0
  rrnPaiAtual = 0
  lado = 0

  IF proxRRNLivre = 0 THEN
    rrnAchado = 0
    rrnPai = 0
    ladoPai = 0
    EXIT SUB
  END IF

  rrnAtual = RRNPRIMEIRONO&

  DO WHILE rrnAtual <> 0 AND achou = 0
    CALL LeNoNav(rrnAtual, cpfAtual, esq, dir)
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

' Insere CPF novo, ou reaproveita (reativa) um no marcado como removido
SUB InsereOuReativa (reg AS NoCliente, sucesso AS INTEGER, reativado AS INTEGER)
  DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM novoRRN AS LONG
  DIM regPai AS NoCliente
  DIM regExistente AS NoCliente

  CALL Busca(reg.cpf, achou, rrnAch, rrnPai, ladoPai)

  IF achou THEN
    CALL CarregaRegistro(rrnAch, regExistente)
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
    CALL GravaRegistro(rrnAch, regExistente)

    qtdExcluidos = qtdExcluidos - 1
    sucesso = -1
    reativado = -1
    EXIT SUB
  END IF

  proxRRNLivre = proxRRNLivre + 1
  novoRRN = proxRRNLivre
  reg.esquerda = 0
  reg.direita = 0
  reg.excluido = 0
  CALL GravaRegistro(novoRRN, reg)

  IF rrnPai <> 0 THEN
    CALL CarregaRegistro(rrnPai, regPai)
    IF ladoPai = ESQUERDO% THEN
      regPai.esquerda = novoRRN
    ELSE
      regPai.direita = novoRRN
    END IF
    CALL GravaRegistro(rrnPai, regPai)
  END IF

  qtdInseridos = qtdInseridos + 1
  sucesso = -1
  reativado = 0
END SUB

' Assert simples: grava OK/FALHA no log e conta falhas
SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
  IF esperado = obtido THEN
    PRINT #7, "OK    - "; descricao
  ELSE
    PRINT #7, "FALHA - "; descricao; " | esperado=["; esperado; "] obtido=["; obtido; "]"
    totalFalhas = totalFalhas + 1
  END IF
END SUB
