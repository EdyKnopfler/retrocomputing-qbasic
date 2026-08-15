# Armadilhas / gotchas conhecidos

Lista de coisas fáceis de errar por serem específicas do QBasic ou da
arquitetura escolhida, não óbvias a partir do código.

## `COMMON`/`COMMON SHARED` casa por posição, não por nome

* `CHAIN` casa variáveis de `COMMON` pela **ordem de declaração e tipo**,
  não pelo nome — ordem diferente ou variável esquecida desalinha os
  topos de árvore silenciosamente (sem erro, só dado errado)
* **Regra:** todo módulo da corrente replica a `COMMON SHARED` idêntica,
  na mesma ordem, mesmo sem usar todas as variáveis
* Vale também pra `CONST` de tamanho de array compartilhado — valor
  diferente entre módulos gera array de tamanho diferente, mesmo efeito

## `COMMON SHARED` de array exige `AS`, mesmo já tendo `DIM` com tipo

* `COMMON SHARED nomeArray()` sem `AS tipo` dá erro **"AS clause
  required"**, mesmo com `DIM` anterior já tipado.
* Repetir o tipo na linha do `COMMON`:
  ```basic
  DIM cacheClienteChave(1 TO 50) AS STRING * 11
  COMMON SHARED cacheClienteChave() AS STRING * 11   ' AS obrigatorio
  ```
* Confirmado no `QBASIC.EXE` de verdade (dialogo modal em tela),
  `SISTEMA.BAS`/`CLIENTES.BAS`, 2026-08-09.

## `CHAIN` reinicia o módulo do topo — setup não-idempotente precisa de guarda

* `CHAIN "X.BAS"` sempre roda `X.BAS` do início — inicialização fora de
  `SUB`/`FUNCTION` executa de novo a cada volta
* Arquivo aberto sobrevive ao `CHAIN`; reabrir o mesmo número (`#1`) de
  novo dá erro "file already open"
* **Confirmado:** `DIM`/`COMMON SHARED` re-executado na volta de um
  `CHAIN` **não apaga** valor recebido via `COMMON` (escalar, `TYPE` ou
  array estático) — harness de sentinela em
  `testes/SISVALID.BAS`/`testes/CLIVALID.BAS`, `QBASIC.EXE`
* **Padrão adotado:** flag em `COMMON SHARED` (`indicesCarregados AS
  INTEGER`) guardando o setup de rodar só 1x por sessão. Ver
  `SISTEMA.BAS`:
  ```basic
  IF indicesCarregados = 0 THEN
    ' abre arquivos, monta cache - so 1x por sessao
    indicesCarregados = -1
  END IF
  ```

## Limite de 64KB por array

* QBasic não suporta "huge arrays" (só o BASIC PDS com `/AH`) — teto de
  65536 bytes **por array**, não pelo total de estática disponível. Ver
  [[arquitetura-tecnica]]

## Risco de degeneração sob endereçamento implícito (posicional)

* Endereçamento implícito (`n*2`/`n*2+1`) + inserção em sequência
  crescente (ex.: código de barras em lote, ordem do fornecedor)
  degenera a árvore numa corrente quase linear — RRN **dobra a cada
  nível**, estoura array/arquivo em poucas dezenas de inserções
* **Confirmado e descartado** — evidência e decisão final (ponteiros
  explícitos) em [[decisoes]]. Mantido aqui só como lembrete pra não
  repetir o erro

## Convenção de nó zerado exige write-through

* Regra "RRN pequeno → array; RRN grande → arquivo; RRN zero → não
  existe" só funciona se o array em RAM for espelho exato dos primeiros
  N registros do arquivo — toda escrita nessa faixa precisa ir nos dois
  lugares, senão a busca continua "achando" a versão antiga no array

## Arquivos-fonte `.BAS`: só ASCII puro, com CRLF

* Sem acento/caractere fora de `0x00-0x7F` — um só já corrompeu o parser
  do editor DOS (linhas se fundiram visualmente, erro de sintaxe num
  ponto sem relação aparente com o acento)
* Terminador de linha CRLF, não LF
* Checar fora do DOS: `file arquivo.BAS` deve dizer "ASCII text, with
  CRLF line terminators"

## RRN de arquivo randômico começa em 1, não em 0

* `GET`/`PUT` de arquivo `RANDOM`: `recordnumber` válido é **1 a
  2147483647** — registro 0 não é permitido (manual QBasic, statement
  `GET`: "The first record or byte position in a file is 1")
* Diferente de array QBasic puro (que aceita índice 0) — não confundir
  com protótipos só-em-memória (`ARVORE.BAS`/`teste4.bas`), que podem
  ter usado índice 0 livremente
* **Implicação de desenho:** cabeçalho do índice não pode ficar no RRN
  0. Em índice **secundário** com cabeçalho próprio (`ARVDISCO.BAS`),
  isso significa `RRNHEADER& = 1` e primeiro nó em `RRNPRIMEIRONO& = 2`.
  Convém também porque RRN 0 já é usado como sentinela de "subárvore
  vazia" em `esquerda`/`direita` — se fosse um registro real gravável, a
  convenção ficaria ambígua
* Índice **primário** autoindexado (`testes/CADCLI1.BAS`/`CADCLI2.BAS`)
  nem precisa de registro de cabeçalho — ver [[decisoes]]
* Confirmado consultando o manual oficial (qbasic.net), 2026-08-14

## `ON ERROR GOTO` cujo rótulo do handler é a linha seguinte não arma a trap

* Rótulo do handler **imediatamente após** a instrução arriscada, sem
  `RESUME` explícito (handler = ponto de continuação, alcançado só por
  fluxo normal quando não há erro), **não funciona** — erro não
  trapeado, cai no diálogo modal do `QBASIC.EXE` mesmo com `ON ERROR
  GOTO` ativo. Confirmado no `QBASIC.EXE` de verdade, `testes/
  CADCLI1.BAS`, 2026-08-15 (usuário precisou clicar OK manualmente)
* **Causa exata, isolada por teste A/B** (`testes/TESTSYS1.BAS` vs.
  `testes/TESTRES1.BAS`, 2026-08-15): **não** é "qualquer código depois
  do rótulo sem `RESUME` trava". Rótulo seguido só de `PRINT`/`SYSTEM`
  comuns, sem nenhum `ON ERROR` novo, roda liso, sem diálogo. O que
  trava é **tentar executar outro `ON ERROR` (inclusive `GOTO 0`, que
  só desliga o trap) enquanto o trap atual ainda está aberto, sem
  `RESUME`** — é isso que o manual chama de "reaching the end of an
  error-handling routine without finding RESUME" → erro **"No
  RESUME"**. Ou seja: o próximo `ON ERROR` é o marcador de "fim da
  rotina de tratamento" nesse dialeto sem blocos estruturados; só ele
  (não código comum) exige `RESUME` antes
* **Correção:** handler precisa de `RESUME <rótulo>` explícito, com o
  caminho de sucesso pulando o handler via `GOTO` — idioma já usado em
  `ARVDISCO.BAS`/`SISVALID.BAS` e documentado em
  [[convencoes]]:
  ```basic
  ON ERROR GOTO SemArquivo
  KILL "ARQUIVO.DAT"
  GOTO Apagou
  SemArquivo:
  RESUME Apagou
  Apagou:
  ON ERROR GOTO 0
  ```
* Não usar o atalho de "rótulo único, sem RESUME, caindo direto por
  fluxo normal" mesmo parecendo equivalente na leitura
* **Mecanismo completo do travamento** (confirmado com repro isolado,
  `testes/TESTSYS1.BAS`/`TESTSYS2.BAS`, 2026-08-15, reproduzido 2x):
  diálogo do erro não é só "clicar OK" — precisa de **OK → F5 (retomar
  execução) → sair da IDE manualmente**, três ações humanas. Só depois
  da saída manual da IDE o DOS volta ao prompt e um `-c` seguinte do
  DOSBox roda. Clicar OK sozinho só fecha o diálogo, não retoma o
  programa
* **A causa não é "deu erro", é "apareceu diálogo".** Erro trapeado sem
  diálogo (idioma com `RESUME` acima) deixa a IDE em modo "executando" o
  tempo todo — `SYSTEM` funciona igual a um programa sem erro nenhum,
  volta ao DOS sozinho. O diálogo modal é que muda o estado da IDE pra
  "parado no editor", e só saída manual da IDE tira desse estado —
  `SYSTEM` não sabe fazer isso. Por isso o idioma com `RESUME` resolve
  de vez o encadeamento via `-c` do DOSBox, não é só estilo mais limpo

## `DIR$` não existe neste dialeto

* Idiomatismo de Visual Basic, não de QBasic/QuickBASIC
* Pra checar se arquivo existe antes de `OPEN ... FOR RANDOM` (que cria
  se não existir): `ON ERROR GOTO` + `OPEN ... FOR INPUT` (erro = não
  existe), ou `LOF(1) = 0` depois de abrir em modo RANDOM. Confirmado em
  `testes/ARVDISCO.BAS`, `QBASIC.EXE`

## `ON ERROR GOTO <rótulo>` só vale no programa principal

* Rótulo não pode ficar dentro de `SUB`/`FUNCTION` — diferente de
  Visual Basic
* Pra decidir algo (ex.: "arquivo já existe?") dentro de uma rotina
  chamada por uma SUB: resolver no programa principal, antes da
  chamada, guardando o resultado numa `SHARED` que a SUB só lê
* Confirmado pelo usuário em 2026-08-08, depois de eu colocar o rótulo
  dentro de `SUB AbreIndice` em `ARVDISCO.BAS` por engano

## `TYPE...END TYPE` tem que vir antes de qualquer `DECLARE` que o use

* `DECLARE SUB Foo (x AS MeuTipo)` **antes** de `TYPE MeuTipo...END TYPE`
  no arquivo dá erro **"Type not defined"** no `QBASIC.EXE`, cursor no
  parâmetro do tipo indefinido — mesmo o `TYPE` estando definido mais
  abaixo no mesmo arquivo
* Diferente de `SUB`/`FUNCTION` (podem ser declaradas antes de
  definidas, é pra isso que serve `DECLARE`) — `TYPE` não tem essa
  flexibilidade, ordem física no arquivo importa
* **Ordem correta:** todo bloco `TYPE...END TYPE` usado em algum
  `DECLARE` vem antes do bloco de `DECLARE SUB`/`DECLARE FUNCTION`
* Confirmado ao vivo no `QBASIC.EXE`, `testes/CLIVAL1.BAS`, 2026-08-15
  (usuário reportou o diálogo); mesmo erro existia em `CLIENTES.BAS`
  (TYPE depois do bloco DECLARE), corrigido junto

## Cliente "Consumidor" (ID 0) não é um registro real

* Não buscar ID 0 na árvore de clientes — não existe lá por design (ver
  [[regras-de-negocio]]). Fluxo de venda trata como caso especial antes
  de qualquer busca de índice
