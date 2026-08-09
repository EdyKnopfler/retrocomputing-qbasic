# Arquitetura técnica

## Ambiente

MS-DOS + QBasic puro (sem `$INCLUDE`, sem módulos carregáveis — recursos
exclusivos do QuickBasic pago). Modularização via SUBs/FUNCTIONs e, quando
o programa cresce demais para a memória, via `CHAIN` com variáveis
`COMMON SHARED` entre programas encadeados.

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

Técnica clássica (originalmente vista em livro dos anos 80 sobre BASIC com
linhas numeradas): os nós de **topo** da árvore ficam carregados num
**array em memória** (cache quente, para consultas rápidas sem I/O), e o
restante da árvore vive no **arquivo randômico** em disco, endereçado por
RRN (relative record number) como se fosse um ponteiro manual. É, na
prática, uma emulação manual de alocação dinâmica/heap (que o QBasic não
tem) usando o disco como "heap" e o array como cache de tamanho fixo.

### Conteúdo e navegação do nó (decidido)

**Navegação: ponteiros explícitos.** Nó guarda `RRN_esquerda` e
`RRN_direita` como campos próprios (`LONG`), não endereçamento implícito
(filho de `n` em `n*2`/`n*2+1`). RRN de cada nó é sua posição real de
inserção (alocação linear via contador), sem relação aritmética com a
profundidade da árvore.

O endereçamento implícito foi cogitado (economiza ~8 bytes/nó, relevante
perto do teto de 64KB por array) mas **descartado por evidência
empírica**: `/home/ederson/Documentos/DOS/projeto/testes/teste3.bas`
tentou essa fórmula e o próprio comentário no arquivo registra que "os
nós não balanceados se prolongam muito além dos limites do array" —
precisou de 10x o espaço (`nChaves * 10`) pra sobreviver a 800 chaves
reais. O risco de fundo: inserção sequencial de chaves (comum quando
código de barras é cadastrado em lote, em ordem crescente do fornecedor)
degenera a árvore numa corrente quase linear, e a posição de cada nó
nessa corrente dobra a cada nível — poucas dezenas de inserções nessa
ordem já ultrapassam qualquer limite razoável de array ou arquivo. Ver
registro histórico em [[armadilhas]] e [[decisoes]].

**Array de RAM (cache do topo): SoA, não `TYPE`.** Arrays paralelos — um
de chaves, um de RRN-esquerda, um de RRN-direita, um de RRN-do-dado
quando aplicável — em vez de um único array de `TYPE`. Motivo: cada
array tem seu próprio teto de 64KB, então o campo mais largo (a chave)
vira o único limitante, quase dobrando a capacidade de nós cacheados
comparado a um array de `TYPE` (soma de todos os campos contra o mesmo
teto). **Não é ganho de performance** — o 80286 não tem cache on-chip (L1
só chegou no 486), então localidade de memória não é argumento aqui; é
puramente capacidade. Essa decisão vale só para o array de RAM: o
**arquivo** de índice em disco não tem limite de 64KB (`GET`/`PUT`
trabalha registro a registro) e pode/deve usar `TYPE` normalmente, por
ser melhor engenharia — carregar do arquivo pro array de RAM exige
"desempacotar" os campos do `TYPE` nos arrays paralelos.

**Índice separado do arquivo de dados, exceto para a chave primária.**
Índice não é autoindexado em geral — o motivo não é densidade de cache
(o array de topo só guarda campos magros de navegação de qualquer forma),
é suportar **múltiplos índices por entidade sem duplicar o payload** (o
dado mora num arquivo só, apontado por RRN a partir de quantos índices
existirem). Refinamento: o índice **primário** de cada entidade (código
de barras pra produto, CPF pra cliente) é autoindexado mesmo assim — sem
campo `dadoRRN`, porque a posição do nó já é a posição do dado — porque é
a chave de maior volume de acesso e elimina uma indireção no caminho mais
comum. Índices **secundários** futuros (ex.: busca por nome) continuam
separados, com ponteiro pro RRN no arquivo primário. Detalhamento
completo em [[decisoes]] (ainda em aberto se busca por nome entra no
escopo).

**Protótipos de referência** (validam ponteiros explícitos + alocação
linear em memória, ainda sem backing em arquivo):
`/home/ederson/Documentos/DOS/projeto/testes/ARVORE.BAS`,
`teste4.bas`, `teste5.bas`. `teste3.bas` documenta a tentativa descartada
de endereçamento implícito.

### Convenção de nó zerado / fora do array

RRN pequeno (dentro da capacidade do array em RAM) → o nó é lido
diretamente do array. RRN maior que a capacidade do array → o nó é
buscado no arquivo via `GET`. RRN igual a 0 (ou chave zerada) → não existe
nó ali (subárvore vazia); é o estado inicial de um cadastro sem registros.

**Invariante que precisa ser respeitada pelo código de inserção:** o
array em RAM é espelho exato dos primeiros N registros do arquivo de
índice (RRN 1..N) — toda escrita num nó cujo RRN caia dentro dessa faixa
precisa ser feita nos dois lugares (write-through), senão a regra "RRN
pequeno → olha o array; RRN grande → dá GET no arquivo" quebra
silenciosamente. Ver [[armadilhas]].

## Memória e `CHAIN`

### Orçamento medido

Medição feita rodando `PRINT FRE(-1), FRE(-2), FRE("")` em ambiente de
teste (ver `SISTEMA.BAS`):

| Área | Bytes livres |
|---|---|
| Alocação estática (arrays/variáveis) | 157972 |
| Stack | 1052 |
| Strings | 30884 |

A alocação estática é a mais relevante: é de onde saem os arrays de topo
de árvore (clientes por CPF, produtos por código de barras) mantidos como
`COMMON SHARED`.

### Limite de 64KB por array

QBasic (diferente do BASIC PDS com `/AH`) não suporta "huge arrays": um
único array `DIM`'d não pode passar de 65536 bytes, por limite de
segmento. Isso vale mesmo que o orçamento total de estática (157972B)
comportasse um array maior — o teto de 64KB é por array individual, não
pelo total.

Estimativa de capacidade do array de produtos (chave = código de barras
EAN-13, 13 bytes fixos), sob o teto de 64KB:

| Esquema de nó | Bytes/nó | Nós/array (64KB) |
|---|---|---|
| Ponteiros explícitos (chave + RRN esq. + RRN dir. + RRN dado, todos `LONG`) | 25 | ~2620 |
| Endereçamento implícito (chave + RRN dado) | 17 | ~3855 |

Com "algumas milhares" de produtos no porte alvo (ver
[[regras-de-negocio]]), o topo em RAM nunca cobre o cadastro inteiro em
nenhum dos dois esquemas — uma fração sempre fica só no arquivo, o que é
o comportamento já previsto pela arquitetura (nó fora do array → busca no
arquivo).

Já o array de clientes por CPF (11 bytes, "algumas centenas" de
registros) cabe inteiro em RAM com folga em qualquer um dos dois esquemas
(poucos KB no total). **Conclusão prática:** não há uma divisão
delicada do orçamento entre os dois índices — clientes usa o pouco que
precisa, e produtos usa o máximo que o teto de 64KB por array permitir.

### `COMMON SHARED` entre módulos encadeados

Ver [[armadilhas]] para a armadilha de alinhamento posicional do
`COMMON`. Arquivos abertos sobrevivem ao `CHAIN` (não fecham
automaticamente), mas a estratégia adotada aqui é manter os topos de
árvore inteiramente em `COMMON SHARED` (RAM), evitando I/O de disco ao
navegar entre cadastro de clientes, cadastro de produtos e a tela de
vendas.

## Vendas

Armazenadas em **arquivos sequenciais, um por mês**, já **denormalizados**
(gravando dados de cliente, produto etc. diretamente no registro de
venda, sem precisar buscar as referências depois).

## Relatórios

Gerados por **external sort** sobre os arquivos de vendas do mês, para
ordenar e agrupar (por produto, por cliente, por dia). Os agregados
mensais resultantes são salvos; agregar o ano é apenas somar os agregados
dos 12 meses já calculados (sem reprocessar o detalhe).

## Reindexação periódica

Ver [[reindexacao]] para o processo completo (external sort + bisseção).

## Duplicação de código

Sem `$INCLUDE`/units, a árvore binária (e os algoritmos de external sort
e rebalanceamento) precisam ser **replicados manualmente** em cada módulo
que usa uma estrutura de dados diferente (cliente por CPF, produto por
código de barras etc.).

Decisão: **aceitar a duplicação** deliberadamente, em vez de investir em
geração de código ou abstração via `CHAIN`/templates textuais — já foi
tentada uma abordagem de concatenação de fontes ("compilação" por
concatenação) no passado e considerada exaustiva e difícil de debugar (só
dá para debugar a versão "compilada", não os fontes separados).

Estratégia de mitigação escolhida (leve, sem ferramenta): **nomear cada
algoritmo com um comentário no código** (ex.: `' ALGORITMO: busca em
arvore binaria por chave string`) em cada ocorrência, mais um **índice em
arquivo .txt** listando os arquivos/linhas onde cada algoritmo nomeado
aparece — assim, ao corrigir um bug numa cópia, dá para localizar as
demais cópias que precisam da mesma correção.

## Padrão geral do projeto

Todas as estruturas principais seguem o mesmo padrão de "processar em
blocos, fazer spill para o disco quando o bloco fecha, e consolidar
depois":

| Componente | Bloco em memória | Spill | Consolidação |
|---|---|---|---|
| Árvore | Nós de topo em array | Resto no arquivo | Reindexação por bisseção |
| External sort | Runs que cabem em memória | Runs gravadas em disco | Merge das runs |
| Relatórios | Agregado do mês | Agregado mensal salvo | Soma dos agregados = ano |
