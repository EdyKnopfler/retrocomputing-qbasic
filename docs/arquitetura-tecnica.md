# Arquitetura técnica

## Ambiente

* MS-DOS + QBasic puro — sem `$INCLUDE`/módulos carregáveis (exclusivos
  do QuickBasic pago)
* Modularização via SUBs/FUNCTIONs; quando o programa não cabe na
  memória, via `CHAIN` + `COMMON SHARED` entre programas encadeados

## Cadastros (clientes, produtos)

- Armazenados em arquivos de acesso **randômico** (`RANDOM`), registro de
  tamanho fixo (`TYPE...END TYPE`, `GET`/`PUT`).
- Indexados por **árvores binárias simples** (não B-trees/B+trees —
  decisão consciente de manter simples), também persistidas em arquivos
  randômicos (um arquivo de índice por chave de busca).
- Índices desta aplicação: **cliente por CPF**, **produto por código de
  barras**. Um leitor de código de barras ajuda o usuário na entrada (ver
  [[regras-de-negocio]]).
- Chaves normalizadas para comparação uniforme: strings de tamanho fixo
  (CPF com zeros à esquerda se necessário, código de barras em formato
  fixo EAN), o que permite que a lógica de busca/inserção da árvore seja
  a mesma independentemente do tipo de chave.

## Árvore binária em array + arquivo

* Técnica clássica (livro dos anos 80 sobre BASIC com linhas numeradas):
  nós de **topo** num **array em RAM** (cache quente), resto no
  **arquivo randômico** em disco, endereçado por RRN como ponteiro manual
* Emula alocação dinâmica/heap (que QBasic não tem): disco como "heap",
  array como cache de tamanho fixo

### Conteúdo e navegação do nó (decidido — motivo/evidência em [[decisoes]])

* **Navegação: ponteiros explícitos.** `RRN_esquerda`/`RRN_direita`
  (`LONG`) como campos próprios, não endereçamento implícito
  (`n*2`/`n*2+1`). RRN = posição real de inserção (contador linear), sem
  relação com profundidade da árvore
* **Array de RAM: SoA, não `TYPE`.** Arrays paralelos (chave,
  RRN-esquerda, RRN-direita, RRN-dado) — cada um sob seu próprio teto de
  64KB, quase dobrando a capacidade de nós cacheados vs. um array de
  `TYPE`. Não é ganho de cache de CPU (286 não tem L1), é só capacidade.
  Vale só pro array de RAM — o **arquivo** usa `TYPE` normalmente (sem
  teto de 64KB)
* **Índice separado do dado, exceto no primário.** Separado permite
  múltiplos índices por entidade sem duplicar payload. O índice
  **primário** (código de barras/CPF) é autoindexado (sem `dadoRRN` —
  posição do nó já é a posição do dado). Índices secundários futuros
  (ex.: busca por nome — ainda em aberto) continuam separados

**Protótipos de referência:**

* Só em memória: `testes/ARVORE.BAS`, `teste4.bas`, `teste5.bas`.
  `teste3.bas` = tentativa descartada de endereçamento implícito
* Com backing em arquivo, índice secundário completo, validado no
  `QBASIC.EXE`: `testes/ARVDISCO.BAS`. Números/detalhes da carga: [[decisoes]]

### Convenção de nó zerado / fora do array

* RRN dentro da capacidade do array → lido do array em RAM
* RRN além da capacidade → busca no arquivo via `GET`
* RRN 0 → subárvore vazia (nó não existe)
* **Invariante:** array em RAM é espelho write-through dos primeiros N
  registros do arquivo — toda escrita nessa faixa grava nos dois
  lugares, senão a regra acima quebra silenciosamente. Ver [[armadilhas]]
* Confirmado em `ARVDISCO.BAS`: `GET` além do fim do arquivo retorna
  registro zerado sem erro (usado no espelhamento inicial do cache)

## Memória e `CHAIN`

### Orçamento medido

* `PRINT FRE(-1), FRE(-2), FRE("")`, medido ANTES de qualquer array de
  cache existir (`testes/MEMFRE1.BAS`), 2026-08-15:

| Área | Bytes livres |
|---|---|
| Array dinâmico (heap, fora do DGROUP — ver seção abaixo) | 158940 |
| Stack | 1052 |
| Strings | 30124 |

* Esse número mede o pool de **array dinâmico**, não o DGROUP estático
  — é desse pool que os arrays de topo de árvore (`COMMON SHARED`) saem

### Estático vs. dinâmico: dois tetos diferentes, não um só

Descoberto tentando `DIM` estático das arrays de cache no tamanho de
produção (500 clientes / 5041 produtos, ~115KB somados): deu **"Out of
memory"** ao vivo, mesmo com `FRE(-1)` relatando bem mais que isso de
sobra. Causa confirmada no manual (`DIM`, qbasic.net) — detalhe completo
em [[armadilhas]]:

* **Array estático** (`DIM`/`COMMON SHARED` com bounds de `CONST`):
  alocado em tempo de compilação, dentro do **DGROUP** — teto de 64KB é
  do **segmento inteiro**, somando todos os arrays/variáveis estáticos
  juntos, não por array. Cliente+produto juntos nunca cabem aí
* **Array dinâmico** (`REDIM`): alocado em tempo de execução, fora do
  DGROUP (heap) — aí sim o teto de 65536 bytes é **por array
  individual**, e o total entre vários arrays dinâmicos é limitado só
  pelo pool medido por `FRE(-1)` acima, não pelos 64KB do DGROUP
* **Solução adotada:** arrays de cache são **dinâmicos** — declarados
  via `COMMON SHARED nome() AS tipo` (sem bounds) e dimensionados por
  `REDIM` **uma única vez**, só em `SISTEMA.BAS`, dentro do guarda
  `indicesCarregados = 0` (`REDIM` sempre zera o array — rodar de novo
  a cada `CHAIN` apagaria o cache já populado). `CLIENTES.BAS`/
  `PRODUTOS.BAS` só declaram `COMMON SHARED`, nunca `REDIM` — ver
  [[decisoes]]

### Teto de 65536 bytes por array (dinâmico)

Tabela histórica (decisão de ponteiros explícitos + SoA vs. `TYPE`,
contexto de índice **secundário** com `dadoRRN` — ver [[decisoes]]):

| Esquema de nó | Bytes/nó | Nós/array (64KB) |
|---|---|---|
| Ponteiros explícitos (chave 13B EAN + RRN esq./dir./dado, `LONG`) | 25 | ~2620 |
| Endereçamento implícito (chave + RRN dado) | 17 | ~3855 |

Números reais do índice **primário** autoindexado atual (sem
`dadoRRN` — só chave+esquerda+direita, cada campo em array próprio):

| Cache | Campo mais largo | Bytes/elemento | Teto (65536 ÷ bytes) |
|---|---|---|---|
| Cliente (chave CPF) | `cacheClienteChave` | 11 | 5957 |
| Produto (chave EAN-13) | `cacheProdutoChave` | 13 | 5041 |

* `esquerda`/`direita` (`LONG`, 4 bytes/elemento) nunca são o gargalo —
  cabem 16384 elementos nesse teto
* **Capacidade final adotada: 500 clientes / 5041 produtos** — medido e
  validado contra os `.IDX` reais (`testes/MEMFRE2.BAS`,
  `testes/MEMFRE3.BAS`, `testes/SISVAL3.BAS`), sobrando ~40KB livres
  após a carga dos dois índices. Motivo da divisão (não é 25%/75% do
  orçamento): produto já bate o teto de array bem antes de consumir a
  fração de orçamento equivalente — ver [[decisoes]]
* Produtos (algumas milhares, [[regras-de-negocio]]): topo em RAM nunca
  cobre o cadastro inteiro — resto fica no arquivo (comportamento já
  previsto)
* Clientes por CPF (algumas centenas, [[regras-de-negocio]]): 500 de
  cache cobre o porte alvo inteiro com folga

### `COMMON SHARED` entre módulos encadeados

* Armadilha de alinhamento posicional do `COMMON`: ver [[armadilhas]]
* Arquivos abertos sobrevivem ao `CHAIN`
* Topos de árvore ficam inteiramente em `COMMON SHARED` (RAM), evitando
  I/O ao navegar entre cadastro de clientes, produtos e vendas

## Vendas

* Arquivos sequenciais, um por mês, **denormalizados** (dados de
  cliente/produto direto no registro de venda, sem buscar depois)

## Relatórios

* **External sort** sobre os arquivos de vendas do mês (ordena/agrupa
  por produto, cliente, dia)
* Agregados mensais salvos; agregar o ano = somar os 12 meses (sem
  reprocessar detalhe)

## Reindexação periódica

Ver [[reindexacao]] (external sort + bisseção).

## Duplicação de código

* Sem `$INCLUDE`/units: árvore binária, external sort e rebalanceamento
  precisam ser **replicados manualmente** por chave (cliente por CPF,
  produto por código de barras etc.)
* **Duplicação aceita deliberadamente** — concatenação de fontes
  ("compilação" por concatenação) já foi tentada e descartada (só dá
  pra debugar a versão compilada, não os fontes)
* Mitigação leve: **comentário nomeando o trecho repetido** (ex.:
  `' REPETICAO: busca em arvore binaria por chave string`) em cada
  ocorrência, apontando pro **índice** [[duplicacoes]] — que lista
  nome, propósito e arquivos/linhas de cada cópia

## Padrão geral do projeto

Todas as estruturas principais seguem o mesmo padrão de "processar em
blocos, fazer spill para o disco quando o bloco fecha, e consolidar
depois":

| Componente | Bloco em memória | Spill | Consolidação |
|---|---|---|---|
| Árvore | Nós de topo em array | Resto no arquivo | Reindexação por bisseção |
| External sort | Runs que cabem em memória | Runs gravadas em disco | Merge das runs |
| Relatórios | Agregado do mês | Agregado mensal salvo | Soma dos agregados = ano |
