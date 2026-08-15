# Log de decisões

Ordem cronológica. Cada entrada registra a decisão, o motivo, e — quando
relevante — o que foi descartado e por quê. Decisões em aberto ficam
marcadas como tal até serem confirmadas.

## Fundação do projeto

- **QBasic puro, sem `$INCLUDE`/units.** Premissa do exercício de
  "programar para escassez" (ver raiz do [CLAUDE.md](../CLAUDE.md)) —
  não é restrição orçamentária realista, é escolha deliberada do
  exercício.
- **Cadastros em arquivo randômico + árvore binária simples** (não
  B-tree), indexados por array em RAM (topo) + arquivo (resto),
  endereçado por RRN. Ver [[arquitetura-tecnica]].
- **Vendas em arquivo sequencial mensal, denormalizado.** Evita
  precisar buscar referências de cliente/produto depois, ao custo de
  espaço em disco.
- **Relatórios via external sort**, agregados mensais salvos e somados
  para o ano (não reprocessa o detalhe).
- **Reindexação via dump ordenado (external sort) + reconstrução por
  bisseção**, disparada por limiar de exclusões (20–25% sugerido). Ver
  [[reindexacao]].
- **Duplicação de código aceita deliberadamente** entre as cópias do
  algoritmo de árvore/sort para cada chave diferente, e entre modelos de
  dados (`TYPE`) replicados por cadastro. Mitigada por convenção de
  comentário nomeado (`' REPETICAO: ...`) + índice em [[duplicacoes]]
  (não por geração de código ou concatenação de fontes — já tentado e
  descartado antes por ser difícil de debugar).

## 2026-08-08 — Índices de negócio e memória

- **Cliente por CPF, produto por código de barras.** Leitor de código de
  barras é a entrada principal de produto; CPF é o identificador natural
  de cliente quando informado.
- **Cliente "Consumidor" (ID 0) não existe no cadastro** — caso especial
  em código, não registro na árvore. Maioria das vendas não identifica
  cliente. Ver [[regras-de-negocio]].
- **Topos de árvore em `COMMON SHARED`, preservados via `CHAIN`** — evita
  recarregar índice do disco ao navegar entre telas. Armadilha: casamento
  posicional do `COMMON` — ver [[armadilhas]].
- **Orçamento estático medido: 157972 bytes** (+1052 stack, +30884
  strings), via `PRINT FRE(-1), FRE(-2), FRE("")`. Teto pros arrays de
  topo em RAM.
- **Divisão do orçamento entre clientes/produtos não é delicada** —
  clientes (centenas, CPF 11B) cabe com folga; produtos (milhares,
  código de barras 13B) é limitado só pelo teto de 64KB/array, não por
  concorrência entre os dois. Cálculo: [[arquitetura-tecnica]].

### 2026-08-08 — Conteúdo e navegação do nó do índice (fechado)

Pergunta original: "o índice conter apenas a chave e o número do
registro é o bastante?"

- **Ponteiros explícitos** (`RRN_esquerda`/`RRN_direita`), não
  endereçamento implícito (`n*2`/`n*2+1`). Evidência:
  `/home/ederson/Documentos/DOS/projeto/testes/teste3.bas` tentou a
  fórmula posicional — precisou de `nChaves * 10` posições pra
  sobreviver a 800 chaves reais (10x de desperdício; nós desbalanceados
  "se prolongam muito além dos limites do array", no próprio comentário
  do arquivo). `ARVORE.BAS`/`teste4.bas`/`teste5.bas` confirmam que
  ponteiros explícitos + alocação linear não têm esse problema. Ver
  [[armadilhas]].
- **Array de RAM em SoA** (arrays paralelos: chave, RRN-esquerda,
  RRN-direita, RRN-dado), não `TYPE`. Cada campo tem seu próprio teto de
  64KB, então a chave (campo mais largo) vira o único limitante — quase
  dobra a capacidade de nós cacheados vs. um array de `TYPE`. Não é
  ganho de performance (286 não tem cache on-chip, L1 só chegou no 486)
  — é puramente capacidade. Vale só pro array de RAM; o arquivo em disco
  usa `TYPE` normalmente (sem teto de 64KB, `GET`/`PUT` é por registro).
  Cálculo: [[arquitetura-tecnica]].
- **Índice separado do dado** (não autoindexado). Motivo real: suportar
  múltiplos índices por entidade sem duplicar payload (não densidade de
  cache — o array de topo só guarda campos magros de navegação de
  qualquer forma). Autoindexado representaria só uma ordenação; uma
  segunda busca duplicaria o payload inteiro, com risco de dessincronia.
- **Refinamento: índice primário é autoindexado** (sem `dadoRRN` — chave
  de maior volume de acesso, posição do nó já é a posição do dado).
  Índices secundários futuros (ex.: nome) continuam separados, com
  ponteiro pro RRN primário. Custo: acopla navegação da árvore com
  campos de negócio no `TYPE` do índice primário.

### 2026-08-09 — Backing em arquivo do índice: validado (não só desenhado)

`testes/ARVDISCO.BAS` rodou no `QBASIC.EXE` de verdade e confirmou, com
I/O real:

- Dois `TYPE` (nó + cabeçalho) num arquivo `RANDOM` só, sob um `LEN=` comum
- Write-through cache/arquivo via `LeNo`/`GravaNo` como único ponto de acesso
- `Busca`/`Insere` com alocação linear de RRN
- **Persistência entre execuções** — reabrir sem apagar o `.IDX` retoma
  o cabeçalho corretamente
- Carga de 10.000 linhas de CSV: 1.899 chaves distintas, 8.101
  duplicatas, buscas corretas via cache e via arquivo

Cobre índice **secundário** (com `dadoRRN`); primário autoindexado ainda
não prototipado. Detalhes: [[arquitetura-tecnica]].

**Em aberto: múltiplos índices por entidade.** Desenho original previa
busca por nome além de código/CPF — ainda não decidido se entra no
escopo. Não muda a decisão de manter índice separado do dado.

### 2026-08-14 — Índice primário autoindexado: sem registro de cabeçalho

Protótipo (`testes/CADCLI1.BAS`/`CADCLI2.BAS`, cadastro de clientes por
CPF) fecha o caso que tinha ficado em aberto (índice **primário**
autoindexado, sem `dadoRRN` — só o secundário estava validado em
`ARVDISCO.BAS`).

- **Raiz é sempre o RRN 1** (primeiro registro gravado) — não precisa de
  campo `raizRRN` persistido. Alocação é linear/sem gaps e remoção é só
  flag (nó nunca sai do lugar), então nada jamais move a raiz; uma
  reindexação futura escreveria a nova raiz primeiro de novo, mantendo o
  invariante
- **`proxRRNLivre`/`qtdInseridos` derivam de `LOF(1) \ LEN(registro)`**
  — todo slot alocado é uma inserção completa (reativação de nó
  removido reaproveita o RRN, não aloca), então a contagem de registros
  do arquivo já é a resposta, sem precisar persistir contador
- **`qtdExcluidos` não sai do `LOF`** (precisa da flag de cada
  registro), mas é tabulado de graça no mesmo loop que já povoa o cache
  em `AbreArquivo` — sem leitura extra de disco
- **Consequência: nenhum registro de cabeçalho no arquivo.** Ganhos:
  menos 1 `PUT` por inserção/remoção (antes gravava nó + cabeçalho a
  cada operação), e `RRNPRIMEIRONO&` vira `1` em vez de `2` (um RRN a
  mais de capacidade de cache, marginal)
- **Motivo de não ter ficado óbvio de saída:** o truque de "nó zero"
  (`arvore(0)` como raiz fake, ver `ARVORE.BAS` em
  `/home/ederson/Documentos/DOS/projeto/testes/`) só funciona em array
  em RAM — `GET`/`PUT` de arquivo `RANDOM` exige `recordnumber >= 1`
  (manual QBasic, confirmado; ver [[armadilhas]]), então RRN 0 nunca
  poderia ser um registro real de qualquer forma. Isso só ficou claro
  comparando o protótipo em array com a restrição real de arquivo — não
  é uma extrapolação óbvia de um pro outro
- **Reaproveita nó removido na reinserção** (mesmo CPF depois de
  `MarcaRemovido`): sobrescreve os campos de negócio e zera `excluido`
  no mesmo RRN, em vez de criar um nó novo — evita a mesma chave em duas
  posições da árvore. Duplicado **ativo** continua rejeitado

## 2026-08-15 — Capacidade real dos arrays de cache: 500 clientes / 5041 produtos, via array dinâmico

Motivação: os `CONST capacidadeCacheCliente%`/`capacidadeCacheProduto%`
estavam em placeholders pequenos (50/100, "de propósito no kickoff").
Faltava medir o orçamento real e decidir a capacidade de produção.

- **Medição:** `PRINT FRE(-1)` ANTES de qualquer array de cache existir
  (`testes/MEMFRE1.BAS`) deu **158940 bytes** — esse é o pool de array
  **dinâmico** (heap), não o DGROUP estático (só ficou claro depois, ver
  próximo bullet)
- **Tentativa inicial (25%/75% do orçamento) descartada:** 25% de
  158940 dá ~2091 clientes — muito mais que "algumas dezenas" cogitado
  inicialmente. Decisão final não seguiu percentual fixo: partiu de 500
  clientes (folga generosa sobre o porte alvo de "algumas centenas",
  [[regras-de-negocio]]) e maximizou produto dentro do que sobra
- **`DIM` estático de 500+5041 juntos deu "Out of memory" ao vivo**,
  apesar de `FRE(-1)` indicar memória de sobra. Causa raiz, confirmada
  no manual oficial (`DIM`, qbasic.net) — ver [[armadilhas]]: array
  **estático** vive inteiro dentro do **DGROUP**, que tem teto de 64KB
  **pro segmento inteiro** (soma de tudo que é estático), não por array.
  Cliente+produto juntos (~115KB) estouram isso de longe — `FRE(-1)`
  nunca mediu essa restrição porque mede outro pool (o dinâmico)
- **Solução: arrays de cache viraram dinâmicos.** `COMMON SHARED nome()
  AS tipo` (sem bounds) + `REDIM nome(bounds) AS tipo` só em
  `SISTEMA.BAS`, dentro do guarda `indicesCarregados = 0` (`REDIM`
  sempre zera o array — rodar de novo a cada `CHAIN` apagaria o cache
  já populado, por isso tem que ficar preso ao guarda de "só 1x por
  sessão"). `CLIENTES.BAS`/`PRODUTOS.BAS` só têm o `COMMON SHARED`
  (declaração), nunca `REDIM`
- **Validado que `CHAIN` preserva o conteúdo do array dinâmico** sem
  precisar `REDIM` de novo no módulo destino — teste isolado
  `testes/CHAINA1.BAS`/`CHAINB1.BAS` (`REDIM`+popula em A, `CHAIN` pra
  B, B só declara `COMMON SHARED` e lê os valores intactos)
- **`REDIM ... PRESERVE` não existe na QB 1.1** (só na QuickBASIC PDS
  7.1, ausente da doc da QB 1.1) — não é só idiomatismo de VB como se
  pensou a princípio. Sem impacto aqui: só rodamos `REDIM` 1x, em array
  ainda vazio — ver [[armadilhas]]
- **Teto por array dinâmico (65536 bytes) bate exatamente no campo
  chave** — 65536\13 = 5041 produtos, 65536\11 = 5957 clientes (campo
  mais largo do array SoA de cada entidade)
- **Capacidade final: `capacidadeCacheCliente% = 500`,
  `capacidadeCacheProduto% = 5041`** (teto de array). Validado contra
  os `.IDX` reais do usuário (`testes/SISVAL3.BAS`): carga correta (1
  cliente, 2 produtos, valores conferem), `FRE(-1)` sobra ~40848 bytes
  depois da carga completa dos dois índices. **`capacidadeCacheCliente%`
  revisado depois pra 511** (mesmo dia, ver seção de reindexação abaixo)
  — sem custo (bem dentro do teto de 5957), ganha o próximo degrau de
  garantia de profundidade
- Detalhes numéricos e tabelas: [[arquitetura-tecnica]]

## 2026-08-15 — Reconstrução por bisseção: numeração de RRN em largura (não pré-ordem)

Prototipagem de [[reindexacao]] (passo 5 do roteiro, [[plano-de-trabalho]])
ainda não começou em código — esta entrada fecha o desenho antes do
protótipo. Validação empírica do desenho: ver subseção abaixo.

- **Numeração de RRN em largura** (sequência de heap: nível 0 = RRN 1,
  nível `k` = RRN `[2^k, 2^(k+1))`), não em pré-ordem. Motivo: o cache em
  RAM é espelho write-through dos **primeiros RRN do arquivo**, não da
  árvore ([[arquitetura-tecnica]], "Convenção de nó zerado/fora do
  array") — só numeração em largura garante que esse prefixo coincida
  com o topo real da árvore, dos dois galhos
- **Pré-ordem cogitado e descartado**: nele, os primeiros RRN são a raiz
  mais um mergulho inteiro pelo galho esquerdo antes de tocar no
  direito — se a capacidade do cache for menor que a subárvore esquerda,
  o cache fica sem nenhum nó do lado direito, por mais raso que seja.
  Pior que a numeração por ordem de inserção já usada hoje (que ao menos
  tende a favorecer nós de ambos os lados, por mecânica natural de
  inserção em BST)
- **Não é só teórico — bate direto na carga do índice na inicialização**:
  `AbreIndiceCliente`/`AbreIndiceProduto` ([[duplicacoes]], baseado em
  `AbreIndice` de `testes/ARVDISCO.BAS`) já é uma leitura sequencial dos
  primeiros RRN do arquivo até encher o cache — mecanismo que só carrega
  algo útil se RRN baixo corresponder a raso na árvore. Reindexar em
  pré-ordem não quebraria essa carga (continuaria rodando sem erro nem
  aviso), só encheria o cache com um subconjunto torto — degradação
  silenciosa, do mesmo tipo que [[armadilhas]] já cataloga
- **Numeração em largura via aritmética pura, `RRN_esquerda = 2*base` /
  `RRN_direita = 2*base+1` com `mid` arredondado pra cima: tentada e
  descartada.** Hipótese era que isso reproduzia o formato de árvore
  completa (heap-shape) pra qualquer N — verificado por simulação
  (`analise_numeracao.py`) que bate com o formato correto em só 1 de 199
  tamanhos de árvore testados (só N=1, trivial). A divisão
  esquerda/direita de árvore completa depende de quantos nós sobram no
  último nível parcialmente preenchido, não é uma fórmula simples de
  arredondamento — não compensa calcular só pra evitar a fila
- **Numeração em largura exige fila explícita** de faixas pendentes (não
  cabe só na pilha de recursão, que só acompanha profundidade, não
  largura de nível): RRN atribuído no momento em que o nó é enfileirado
  — mesmo mecanismo de "próxima posição livre" já usado na inserção
  normal, sem fórmula fechada. Motivo de precisar da fila: largura não
  preserva "subárvore = faixa contígua de RRN de saída" (propriedade que
  pré-ordem tinha) — uma subárvore em largura fica espalhada entre
  vários níveis, então gravar em bloco exige processar nível a nível
- **Buffer de saída: obrigatório, não é otimização especulativa.** Sem
  ele, a aplicação intercala `GET` (dump) / `PUT` (saída) registro a
  registro. O MS-DOS é monotarefa — executa exatamente a sequência de
  chamadas que a aplicação emite, sem reordenar — então disparar uma
  rajada de gravação sequencial em vez de intercalar nunca é pior,
  **independente de `BUFFERS=`** (no pior caso empata, no melhor caso
  evita alternância de verdade); não precisa medir pra justificar a
  decisão, só mediria o tamanho do ganho. Acumula nós do topo (via fila)
  num buffer em memória; ao fechar um nível, 1 seek + gravação
  sequencial do buffer inteiro
- **Em aberto**: o atalho "faixa cabe no buffer, resolve tudo de uma vez
  em memória" não pode disparar só por tamanho — se disparar enquanto
  sub-árvores irmãs do mesmo nível (ou mais rasas) ainda estão pendentes
  na fila, numera/grava aquele pedaço fora de ordem, furando a garantia
  "nível completo antes de avançar". Precisa ser condicionado à
  profundidade (só liberar depois que a faixa relevante pro cache já foi
  processada nível a nível) — desenho ainda não fechado, avaliar no
  protótipo

### 2026-08-15 — Reconstrução por bisseção: validada (não só desenhada)

`testes/REINDEX1.BAS` rodou no `QBASIC.EXE` de verdade e confirmou, com
I/O real, o desenho acima (fila FIFO, largura, buffers pequenos de
propósito no teste — 100 registros de entrada/saída, 1000 registros no
total):

- **8/8 verificações OK**: nós gravados = total; percurso em-ordem via
  ponteiros reproduz a sequência ordenada original (bissecção + amarração
  de ponteiros corretos); profundidade máxima 9 (dentro do teto teórico
  ⌈log2(1000)⌉=10); **BFS independente** (percorre o arquivo final pelos
  ponteiros, sem depender de como foi montado) confirma RRN visitado em
  sequência estrita 1,2,3...1000 — numeração em largura de verdade, não
  só por construção
- **Buffer de saída: previsão bate exata com a medição** — 10 seeks
  (1000/100), sempre sequencial. Não é coincidência: como a fila FIFO
  garante RRN de destino crescente em sequência estrita (provado no
  desenho acima), a escrita nunca precisa reordenar nada, só acumular e
  despejar
- **Buffer de entrada: reduz de 1000 pra 71 seeks** (929 leituras vieram
  do buffer, sem I/O nenhum) — evidência de que a fila processa faixas da
  esquerda pra direita dentro de cada nível, então `mid`s consecutivos
  tendem a cair perto uns dos outros no dump mesmo alternando entre
  subárvores irmãs
- **Técnica de bloco confirmada no manual, não suposta**: `GET`/`PUT` com
  número de registro omitido continua sequencialmente da posição do
  `GET`/`PUT` anterior, sem seek (qbasic.net) — usada de verdade no
  protótipo pro "1 seek + rajada sequencial" de cada bloco
- Dois gotchas de sintaxe novos, sem relação com o desenho em si
  (identificador com underscore; `POS` como nome de parâmetro, mesmo com
  sufixo de tipo) — [[armadilhas]]

**Fora do escopo deste protótipo** (não invalida a validação acima, só
não cobre): dump gerado já ordenado direto, sem rodar external sort de
verdade (passo 3 do roteiro, [[plano-de-trabalho]], ainda não
prototipado); o atalho de buffer cruzando fronteira de nível continua em
aberto (bullet acima); escala de teste (1000 registros, buffer de 100) é
bem menor que produção (milhares de produtos) — só valida a lógica, não
tempo real de I/O em hardware de época.

### Limite do invariante "início do arquivo = topo da árvore": garantia é de N, não de K

O invariante "início do arquivo = topo da árvore" (o que permite carregar
o cache com uma leitura sequencial simples) **não é tudo-ou-nada** — é uma
garantia que cresce em degraus, independente da capacidade do array:

- **A garantia é propriedade de N (quantos registros existiam na última
  reindexação), não de K (capacidade do cache).** Numa árvore em largura,
  a profundidade `d` só fica **100% sem buraco** quando N ultrapassa
  `2^(d+1) - 1` — os degraus são 511, 1023, 2047, 4095, 8191... Assim que
  N passa de um desses números, tudo até aquela profundidade está
  garantido, **de graça, sem depender de K nem um pouco** — K só decide
  quanto *além* dessa garantia cabe no cache
- **Faixa sem garantia**: entre N e K sobra uma faixa preenchida por
  inserção avulsa depois da reindexação (não pela bisseção limpa) — sem
  garantia de profundidade nenhuma ali, o que cai é o que a ordem de
  chegada das inserções trouxer. Pra produtos (K=5041, próximo degrau de
  garantia abaixo dele = 4095), essa faixa "de sorte" chega a ~946
  posições (~1/5 de K) — nunca faz mal ter essa faixa (mais capacidade
  nunca piora nada), só não dá pra contar com ela como garantida
- **Se o cadastro inteiro cabe no cache (N ≤ K), a degeneração da árvore
  não importa — pode até deixar degenerar.** "Cacheado" e "existe" viram
  a mesma coisa quando ninguém fica de fora (todo RRN ≤ N ≤ K está no
  cache por definição), então não há distinção nenhuma entre nó raso e
  fundo pra fazer. Esse é o caso de clientes (K=500 já dimensionado com
  folga sobre "algumas centenas", [[regras-de-negocio]]) — na prática,
  o problema desta seção só existe pra cadastros que rotineiramente
  ultrapassam a capacidade do cache (produtos)
- **Decisão: usar a capacidade máxima do array (K=5041 produtos, ~500
  clientes), sem cortar pra um "limiar seguro" artificial** (ex.: 4095,
  cogitado e descartado). Cortar K não aumenta garantia nenhuma — a
  garantia depende só de N cruzar o próprio degrau, nunca de K — cortar
  só jogaria fora capacidade de bônus sem eliminar risco algum,
  garantindo aliás que aquela faixa **sempre** vá pro disco, quando com
  K máximo ela pode ser lida da RAM em vez disso (verificado por
  simulação, `verifica_ponto_usuario.py`: profundidade≤11 idêntica e
  100% garantida com K=4095 e com K=5041, mesma N)
- **Risco real remanescente**: reindexar com N abaixo do primeiro degrau
  relevante (511/4095) deixa buracos rasos que inserções orgânicas podem
  preencher fora do cache — verificado por simulação
  (`verifica_invariante2.py`, N=3000, K=5041, 6000 inserções): 386 de
  3959 nós não cacheados pousaram tão rasos quanto o topo garantidamente
  cacheado. Esse risco não muda com K (é sobre N, não sobre K) — a
  mitigação real é gatilho de reindexação também por crescimento do
  cadastro, não só razão de exclusão, pra encurtar o tempo com N pequeno
- **Em qualquer caso, é degradação de desempenho, não de correção** — a
  busca sempre acha o registro certo, via ponteiro explícito; o único
  custo de cair fora da faixa garantida é 1 acesso a disco a mais

**Trade-off de fundo, aceito conscientemente**: é o preço de usar árvore
binária comum + reindexação periódica em vez de B-Tree/B+Tree. B+Tree
rebalanceia a cada inserção — mantém profundidade uniforme o tempo todo,
garantia permanente, sem faixa de sorte nenhuma — mas exige nó com
múltiplas chaves e lógica de split/merge em cascata, bem mais complexa
que busca/inserção binária simples. Esse projeto aceita o oposto
deliberadamente: código simples (mesmo algoritmo de busca/inserção
replicado por chave, [[duplicacoes]]), em troca de a garantia "resetar" a
cada reindexação e uma faixa de ganho não-determinístico entre uma
reindexação e a próxima — coerente com a premissa de "programar pra
escassez" da raiz do [CLAUDE.md](../CLAUDE.md)

## 2026-08-15 — External sort genérico: validado (mecanismo de runs + merge)

Passo 3 do roteiro ([[plano-de-trabalho]]), ainda não prototipado.
`testes/EXTSORT1.BAS` cobre só o algoritmo de ordenação (gerar runs +
merge k-vias), chave-string genérica — sem agregação (passo 4, separado)
e sem plugar ainda no dump de reindexação ([[reindexacao]]) ou em vendas
reais. Motivação de testar a fundo desde já: o algoritmo será
**duplicado** várias vezes (dump de reindexação + relatórios por
produto/cliente/dia), mesmo padrão de [[duplicacoes]].

**Decisões de desenho, fechadas com o usuário antes do protótipo:**

- **Runs num único arquivo** (`RUNS1.DAT`), cada run é uma faixa
  contígua de RRNs — mesma técnica de faixa+seek do `REINDEX1.BAS`, em
  vez de 1 arquivo por run. Motivo: evita abrir 1 handle de arquivo por
  run (risco real de estourar `FILES=` do CONFIG.SYS do DOS conforme o
  número de runs cresce — já mordemos o limite 8.3 de nome antes, ver
  [[plano-de-trabalho]]).
- **Shell sort** (in-place, sem recursão) pra ordenar cada buffer em RAM
  antes de virar run. Motivo: sem array auxiliar (diferente de merge
  sort); sem risco de recursão (já tivemos gotcha de recursão quebrando
  no QBasic, ver [[armadilhas]], caso `BPTREE1.BAS`); sem pior caso
  patológico em entrada já ordenada/revertida (diferente de quicksort
  ingênuo) — relevante porque esses dois casos entraram no roteiro de
  teste abaixo. Vale o código extra por ser duplicado depois.

**Validação:** 31/31 verificações OK, 4 cenários (N=1000
embaralhado+duplicatas/12 runs de BUFRUN=90, N=50 já ordenado, N=50
ordem reversa, N=10 menor que 1 buffer/1 run só): contagem preservada,
cada run individualmente ordenada, saída totalmente ordenada
(comparação adjacente completa, não amostragem), número de runs =
CEIL(N/BUFRUN).

**I/O da geração de runs: totalmente sequencial**, independente de N —
1 seek de entrada + 1 seek de saída. Runs são gravadas em sequência sem
lacuna, então `GET`/`PUT` com número de registro omitido encadeia o
arquivo inteiro (mesma técnica de bloco do `REINDEX1.BAS`).

**I/O do merge: sem bônus de localidade, ao contrário da bisseção do
`REINDEX1.BAS`.** Janela de leitura persistente por run garante que
alternar de qual run é a vez de ler não custa seek (só o esgotamento de
uma janela custa) — mas, diferente do `REINDEX1.BAS` (onde a ordem BFS
fez `mid`s consecutivos caírem perto uns dos outros no dump, dando 71
seeks vs. baseline ~1000), a ordem de leitura do merge é ditada pelas
**chaves** (intercalação de k runs cujas faixas de valor se sobrepõem
inteiramente) — não há vizinhança nenhuma pra explorar. Medido: N=1000,
12 runs, janela=20 → **56 seeks de entrada**, exatamente o teto teórico
(Σ CEIL(tamanhoRun/janela) = 11×5 + 1×1 = 56), não abaixo dele —
confirma a hipótese, não é só uma estimativa pessimista de projeto.
Saída do merge continua puramente sequencial (10 seeks = N/BUFSAI,
mesmo padrão do `REINDEX1.BAS`).

**Fora do escopo deste protótipo** (não invalida a validação acima, só
não cobre):

- **Agregação** (passo 4, separado) — este protótipo só ordena, não
  agrupa/soma.
- **Merge multi-passada**: se o número de runs superar o que cabe em
  janelas simultâneas, precisaria de merge em várias passadas — não
  implementado (porte alvo do projeto não deve gerar runs demais nesse
  ponto; avaliar se a hipótese se sustenta quando o algoritmo for
  duplicado pra um uso real).
- **Plugar em uso real**: dump de reindexação de verdade (troca o
  `GeraDump` fake do `REINDEX1.BAS`) e relatórios mensais por
  produto/cliente/dia — algoritmo ainda não duplicado pra nenhum uso
  real, [[duplicacoes]] não entra ainda.
