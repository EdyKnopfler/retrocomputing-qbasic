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
  algoritmo de árvore/sort para cada chave diferente, mitigada por
  convenção de comentário nomeado + índice em .txt (não por geração de
  código ou concatenação de fontes — já tentado e descartado antes por
  ser difícil de debugar).

## 2026-08-08 — Índices de negócio e memória

- **Cliente indexado por CPF, produto indexado por código de barras.**
  Motivo: leitor de código de barras é o meio de entrada principal para
  produto; CPF é o identificador natural de cliente quando informado.
- **Cliente padrão "Consumidor" (ID 0) não existe no cadastro.** É caso
  especial tratado em código, não um registro na árvore. Motivo: maioria
  das vendas não identifica o cliente; CPF só é informado quando há
  benefício fiscal/da loja em jogo. Ver [[regras-de-negocio]].
- **Topos de árvore (clientes por CPF, produtos por código de barras)
  mantidos em `COMMON SHARED`, preservados através de `CHAIN` entre
  módulos.** Motivo: evitar recarregar índice do disco toda vez que o
  usuário navega entre cadastro de clientes, cadastro de produtos e
  vendas. Armadilha associada: casamento posicional do `COMMON` — ver
  [[armadilhas]].
- **Orçamento de memória estática medido: 157972 bytes** (mais 1052 de
  stack, 30884 de strings), via `PRINT FRE(-1), FRE(-2), FRE("")`. É o
  teto para os arrays de topo de árvore em RAM.
- **Divisão de orçamento entre índice de clientes e de produtos: não é
  uma divisão delicada.** Clientes (algumas centenas, CPF de 11 bytes)
  cabe inteiro em RAM com folga; produtos (algumas milhares, código de
  barras de 13 bytes) é limitado pelo teto de 64KB por array do QBasic,
  não pela concorrência com o array de clientes. Ver cálculo em
  [[arquitetura-tecnica]].

### 2026-08-08 — Conteúdo e navegação do nó do índice (fechado)

Pergunta original: "o índice conter apenas a chave e o número do
registro é o bastante?"

- **Decidido: ponteiros explícitos** (`RRN_esquerda`/`RRN_direita` como
  campos próprios), não endereçamento implícito/posicional (filho de `n`
  em `n*2`/`n*2+1`). Evidência: `/home/ederson/Documentos/DOS/projeto/testes/teste3.bas`
  tentou a fórmula posicional e o próprio comentário no arquivo registra
  que "os nós não balanceados se prolongam muito além dos limites do
  array" — precisou de `nChaves * 10` posições pra sobreviver a 800
  chaves reais (10x de desperdício). `ARVORE.BAS`, `teste4.bas` e
  `teste5.bas` confirmam que ponteiros explícitos + alocação linear
  (contador incremental de próxima posição livre) funcionam sem esse
  problema. Ver [[armadilhas]] para o registro histórico do porquê o
  endereçamento implícito foi descartado.
- **Decidido: array de RAM (cache do topo da árvore) em SoA** (arrays
  paralelos — um de chaves, um de RRN-esquerda, um de RRN-direita, um de
  RRN-do-dado quando aplicável), não `TYPE`/array-de-struct. Motivo: cada
  campo tem seu próprio teto de 64KB por array no QBasic, então o campo
  mais largo (a chave) passa a ser o único limitante — quase dobra a
  capacidade de nós cacheados em RAM comparado a um único array de
  `TYPE`. **Não é uma decisão de performance** (o 80286 não tem cache
  on-chip — L1 só chegou no 486 — o argumento de localidade de cache não
  se sustenta pro hardware alvo); é puramente uma decisão de capacidade.
  Vale só para o array de RAM — o arquivo de índice em disco não tem
  esse limite (`GET`/`PUT` trabalha registro a registro) e pode/deve usar
  `TYPE` normalmente, por ser melhor engenharia. Carregar do arquivo pro
  array de RAM exige "desempacotar" os campos do `TYPE` nos arrays
  paralelos. Ver cálculo de capacidade em [[arquitetura-tecnica]].
- **Decidido: arquivo de índice separado do arquivo de dados** (não
  autoindexado). O motivo **não é** densidade do cache em RAM — o array
  de topo só guarda campos magros de navegação independente de o arquivo
  ser separado ou autoindexado. O motivo real é separação de conceitos e,
  principalmente, suporte a **múltiplos índices por entidade sem
  duplicar o payload** — o dado mora num arquivo só, apontado por RRN a
  partir de quantos índices forem necessários. Um arquivo autoindexado só
  representa uma ordenação; uma segunda busca exigiria duplicar o
  payload inteiro, com risco de dessincronia a cada update/exclusão.
- **Decidido: refinamento — índice primário de cada entidade é
  autoindexado (sem campo `dadoRRN`); índices secundários continuam
  separados, com ponteiro.** Não contradiz a decisão anterior, a precisa:
  só é autoindexado o índice **primário** (código de barras pra produto,
  CPF pra cliente — a chave de maior volume de acesso), onde a posição do
  nó no arquivo/array já *é* a posição do dado, eliminando o campo
  `dadoRRN` (redundante, sempre igual ao próprio RRN) e a indireção extra
  no caminho mais comum. Índices secundários futuros (ex.: busca por
  nome) continuam enxutos e separados, com campo de ponteiro pro RRN no
  arquivo primário — preservando o motivo original de separar (não
  duplicar payload entre múltiplas ordenações). Não piora a densidade do
  cache em RAM (que só guarda campos de navegação, com ou sem payload no
  arquivo). Custo: acopla campos de navegação da árvore com campos de
  negócio no mesmo `TYPE` do índice primário.

**Em aberto: múltiplos índices por entidade.** O desenho original do
projeto (CLAUDE.md antes da reorganização em `docs/`) previa índices por
nome além de código/CPF (ex.: cliente por nome, cliente por código;
produto por nome, produto por código). Ainda não decidido se busca por
nome entra no escopo, ou se cada entidade terá só a chave principal. Não
muda a decisão de manter índice separado do dado (que já se justifica
pela higiene de código, independente de quantos índices existirem).
