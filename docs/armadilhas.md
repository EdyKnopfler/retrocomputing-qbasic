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

## Cliente "Consumidor" (ID 0) não é um registro real

* Não buscar ID 0 na árvore de clientes — não existe lá por design (ver
  [[regras-de-negocio]]). Fluxo de venda trata como caso especial antes
  de qualquer busca de índice
