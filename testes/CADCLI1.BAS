' CADCLI1.BAS - FASE 1
' Prototipo: cadastro de clientes com indice PRIMARIO autoindexado por CPF
' (arvore binaria, ponteiros explicitos, sem dadoRRN separado - a posicao
' do no NA ARVORE ja e a posicao do registro de dado). Caso que ficou em
' aberto em docs/decisoes.md e docs/plano-de-trabalho.md do repo SISTEMA;
' ARVDISCO.BAS cobre so o caso de indice SECUNDARIO (com dadoRRN).
'
' SEM registro de cabecalho. Raiz e SEMPRE o RRN 1 (primeiro registro
' gravado) - alocacao linear/sem gaps garante que nada move a raiz de
' lugar (remocao e so flag, reativacao reaproveita o RRN). proxRRNLivre/
' qtdInseridos saem de LOF(1)\LEN(registro); qtdExcluidos e tabulado no
' mesmo loop que povoa o cache. Ver docs/decisoes.md.
'
' Esta fase cobre: arquivo vazio -> insercoes -> operacoes, tudo dentro
' do MESMO processo (cache em RAM nunca sai da memoria). NAO prova que o
' reload a partir do disco funciona - isso e o CADCLI2.BAS, rodado como
' um QBASIC.EXE separado (processo novo, sem nada em memoria), sem
' apagar o CLIENTE.DAT desta fase. Rodar os dois em sequencia.
'
' Cache SoA em RAM guarda so campos magros de navegacao (cpf/esquerda/
' direita) - NAO guarda nome/endereco/etc, mesmo sendo indice primario
' (decisao de docs/arquitetura-tecnica.md).
'
' Descartavel, nao e arquivo de producao. Roda no QBASIC.EXE via DOSBox,
' resultado gravado em CLIENTE.LOG (OK/FALHA por verificacao).

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
DECLARE SUB MarcaRemovido (cpfProc AS STRING, achou AS INTEGER)
DECLARE SUB Confere (descricao AS STRING, esperado AS STRING, obtido AS STRING)
DECLARE FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)

CONST RRNPRIMEIRONO& = 1          ' tambem e SEMPRE o RRN da raiz - ver cabecalho do arquivo
CONST capacidadeCache% = 500      ' clientes cabem inteiros em RAM com folga (docs/arquitetura-tecnica.md)
CONST RRNULTIMOCACHE& = RRNPRIMEIRONO& + capacidadeCache% - 1
CONST ESQUERDO% = 1, DIREITO% = 2

DIM SHARED cacheCpf(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS STRING * 11
DIM SHARED cacheEsq(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG
DIM SHARED cacheDir(RRNPRIMEIRONO& TO RRNULTIMOCACHE&) AS LONG

DIM SHARED regDisco AS NoCliente
DIM SHARED proxRRNLivre AS LONG   ' = ultimo RRN usado (0 = arvore vazia); deriva de LOF, nunca persistido
DIM SHARED qtdInseridos AS LONG   ' = proxRRNLivre (todo slot alocado e uma insercao; reativacao nao aloca)
DIM SHARED qtdExcluidos AS LONG   ' tabulado no loop de AbreArquivo, nao persistido
DIM SHARED totalFalhas AS INTEGER

' ---------------------------------------------------------------------
' Harness de teste - FASE 1: arquivo vazio, insercoes, operacoes basicas
' ---------------------------------------------------------------------

DIM reg AS NoCliente, reg2 AS NoCliente
DIM achou AS INTEGER, rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
DIM sucesso AS INTEGER, reativado AS INTEGER

' Reinicio limpo - apaga rastro de execucao anterior pra resultado
' deterministico (ON ERROR so vale no programa principal). Handler
' precisa de RESUME explicito - rotulo caindo direto por fluxo normal,
' sem RESUME, NAO armou a trap direito (confirmado no QBASIC.EXE de
' verdade, 2026-08-14/15 - ver docs/armadilhas.md). Mesmo idioma ja
' validado em ARVDISCO.BAS/docs/convencoes.md.
ON ERROR GOTO SemClienteDat
KILL "CLIENTE.DAT"
GOTO ApagouClienteDat
SemClienteDat:
RESUME ApagouClienteDat
ApagouClienteDat:
ON ERROR GOTO 0

ON ERROR GOTO SemClienteLog
KILL "CLIENTE.LOG"
GOTO ApagouClienteLog
SemClienteLog:
RESUME ApagouClienteLog
ApagouClienteLog:
ON ERROR GOTO 0

OPEN "CLIENTE.LOG" FOR OUTPUT AS #7
PRINT #7, "=== CADCLI1.BAS (FASE 1) - arquivo vazio, insercoes ==="

ON ERROR GOTO TrataErro

CALL AbreArquivo
CALL Confere("arquivo comeca vazio (proxRRNLivre=0)", "0", LTRIM$(STR$(proxRRNLivre)))

' --- inserir 3 clientes novos ---
reg.cpf = ChaveFixaCPF$("11111111111")
reg.nome = "Maria Silva"
reg.telefone = "11987654321"
reg.endereco = "Rua A, 100"
reg.complemento = "Apto 12"
reg.cep = "01310-100"
reg.cidade = "Sao Paulo"
reg.uf = "SP"
CALL InsereOuReativa(reg, sucesso, reativado)
CALL Confere("insere cliente 1 (novo)", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))
CALL Confere("cliente 1 vira a raiz (RRN 1)", "1", LTRIM$(STR$(proxRRNLivre)))

reg.cpf = ChaveFixaCPF$("22222222222")
reg.nome = "Joao Souza"
reg.telefone = "21988887777"
reg.endereco = "Av. B, 200"
reg.complemento = ""
reg.cep = "20000-000"
reg.cidade = "Rio de Janeiro"
reg.uf = "RJ"
CALL InsereOuReativa(reg, sucesso, reativado)
CALL Confere("insere cliente 2 (novo)", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

reg.cpf = ChaveFixaCPF$("33333333333")
reg.nome = "Ana Costa"
reg.telefone = "31977776666"
reg.endereco = "Rua C, 300"
reg.complemento = "Fundos"
reg.cep = "30000-000"
reg.cidade = "Belo Horizonte"
reg.uf = "MG"
CALL InsereOuReativa(reg, sucesso, reativado)
CALL Confere("insere cliente 3 (novo)", "-1,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

' --- duplicado ativo deve ser rejeitado ---
reg2.cpf = ChaveFixaCPF$("11111111111")
reg2.nome = "Maria Silva Duplicada"
reg2.telefone = "": reg2.endereco = "": reg2.complemento = ""
reg2.cep = "": reg2.cidade = "": reg2.uf = ""
CALL InsereOuReativa(reg2, sucesso, reativado)
CALL Confere("rejeita CPF duplicado ativo", "0,0", LTRIM$(STR$(sucesso)) + "," + LTRIM$(STR$(reativado)))

' --- busca cliente existente ---
CALL Busca(ChaveFixaCPF$("22222222222"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("busca CPF existente (22222222222)", "-1", LTRIM$(STR$(achou)))
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("nome do cliente 2 apos busca", "Joao Souza", RTRIM$(reg.nome))

' --- busca cliente inexistente ---
CALL Busca(ChaveFixaCPF$("99999999999"), achou, rrnAch, rrnPai, ladoPai)
CALL Confere("busca CPF inexistente (99999999999)", "0", LTRIM$(STR$(achou)))

' --- marca cliente 3 como removido (fica pra FASE 2 confirmar apos reload) ---
CALL MarcaRemovido(ChaveFixaCPF$("33333333333"), achou)
CALL Confere("MarcaRemovido achou cliente 3", "-1", LTRIM$(STR$(achou)))

CALL Busca(ChaveFixaCPF$("33333333333"), achou, rrnAch, rrnPai, ladoPai)
CALL CarregaRegistro(rrnAch, reg)
CALL Confere("excluido=1 apos remocao", "1", LTRIM$(STR$(reg.excluido)))

' --- contadores ao fim da fase 1 (derivados, nunca persistidos) ---
CALL Confere("qtdInseridos = 3 ao fim da fase 1", "3", LTRIM$(STR$(qtdInseridos)))
CALL Confere("qtdExcluidos = 1 ao fim da fase 1", "1", LTRIM$(STR$(qtdExcluidos)))
CALL Confere("LOF(1)\LEN(registro) = 3 (sem registro de cabecalho)", "3", LTRIM$(STR$(LOF(1) \ LEN(regDisco))))

PRINT #7, ""
PRINT #7, "=== FIM FASE 1. Falhas: "; totalFalhas; ". CLIENTE.DAT NAO apagado - rode CADCLI2.BAS em seguida ==="
CLOSE #1, #7

PRINT "FASE 1 OK. Falhas: "; totalFalhas; ". Ver CLIENTE.LOG. Prossiga com CADCLI2.BAS"
SYSTEM

TrataErro:
PRINT #7, "*** ERRO EM RUNTIME (CADCLI1) *** ERR="; ERR; " ERL="; ERL
CLOSE #7
SYSTEM

' ---------------------------------------------------------------------
' REPETICAO: suporte de indice primario autoindexado por CPF - copia
' identica em CADCLI2.BAS (sem $INCLUDE, cada fase e um processo
' QBASIC.EXE a parte). Ver docs/convencoes.md sobre duplicacao aceita.
' ---------------------------------------------------------------------

' Normaliza CPF pra chave fixa de 11 digitos (zeros a esquerda)
FUNCTION ChaveFixaCPF$ (cpfBruto AS STRING)
  ChaveFixaCPF$ = RIGHT$("00000000000" + cpfBruto, 11)
END FUNCTION

' Abre (ou cria - OPEN FOR RANDOM cria sozinho) CLIENTE.DAT. Deriva
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

  ' clientes cabem inteiros no cache (docs/arquitetura-tecnica.md), mas
  ' por seguranca tabula excluidos alem da faixa cacheada se acontecer
  IF totalRegistros > RRNULTIMOCACHE& THEN
    FOR r = RRNULTIMOCACHE& + 1 TO totalRegistros
      GET #1, r, regDisco
      IF regDisco.excluido = 1 THEN qtdExcluidos = qtdExcluidos + 1
    NEXT r
  END IF
END SUB

' Le so os campos de navegacao de um no: do cache SoA se o RRN estiver
' na faixa, senao do arquivo (registro completo, mas so extrai cpf/
' esquerda/direita - excluido/negocio ficam pra CarregaRegistro)
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

' Le o registro completo (todos os campos de negocio + excluido) direto
' do arquivo - usado depois que Busca ja localizou o RRN
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

' Busca por CPF, a partir da raiz (SEMPRE RRN 1 - ver cabecalho do
' arquivo). Compara so a chave - encontra tanto no ativo quanto
' removido (quem chama decide olhando reg.excluido). Devolve pai + lado,
' para permitir insercao subsequente sem buscar de novo. rrnPai=0 quer
' dizer "sem pai" - ou arvore vazia (novo no vira RRN 1, a raiz) ou raiz
' e o proprio no que nao bateu na comparacao mais externa.
SUB Busca (cpfProc AS STRING, achou AS INTEGER, rrnAchado AS LONG, rrnPai AS LONG, ladoPai AS INTEGER)
  DIM rrnAtual AS LONG, rrnPaiAtual AS LONG, lado AS INTEGER
  DIM cpfAtual AS STRING, esq AS LONG, dir AS LONG

  achou = 0
  rrnPaiAtual = 0
  lado = 0

  IF proxRRNLivre = 0 THEN         ' arvore vazia - nao ha RRN 1 gravado ainda
    rrnAchado = 0
    rrnPai = 0
    ladoPai = 0
    EXIT SUB
  END IF

  rrnAtual = RRNPRIMEIRONO&        ' raiz e sempre o primeiro registro gravado

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
' com o mesmo CPF - evita duas posicoes da arvore com a mesma chave.
' Duplicado ativo e rejeitado (sucesso=0). rrnPai=0 no caminho de
' insercao so acontece no 1o registro (novoRRN sai 1 = raiz, de graca -
' nao ha ponteiro de pai pra atualizar).
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

    ' reaproveita o no removido: mantem esquerda/direita da arvore
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

' Marca logicamente removido (excluido=1). No fica na arvore - usado
' na reindexacao periodica (ver docs/reindexacao.md).
SUB MarcaRemovido (cpfProc AS STRING, achou AS INTEGER)
  DIM rrnAch AS LONG, rrnPai AS LONG, ladoPai AS INTEGER
  DIM reg AS NoCliente

  CALL Busca(cpfProc, achou, rrnAch, rrnPai, ladoPai)
  IF achou THEN
    CALL CarregaRegistro(rrnAch, reg)
    IF reg.excluido = 0 THEN
      reg.excluido = 1
      CALL GravaRegistro(rrnAch, reg)
      qtdExcluidos = qtdExcluidos + 1
    END IF
  END IF
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
