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
