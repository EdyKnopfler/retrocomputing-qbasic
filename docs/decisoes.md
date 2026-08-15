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
  depois da carga completa dos dois índices
- Detalhes numéricos e tabelas: [[arquitetura-tecnica]]
