# Sistema de Controle de Lojinha — QBasic/MS-DOS (286)

## Premissa do exercício

Simulação de início dos anos 90: um usuário conseguiu comprar um PC 286 já
defasado (época em que PC era caro) e quer extrair o máximo dele, sem gastar
mais nada — nem em SGBDs comerciais (dBase, Clipper) nem em compiladores
melhores (Turbo Pascal, QuickBasic pago). É um exercício de "programar para
escassez", não uma simulação de restrição orçamentária realista (reconhece-se
que Turbo Pascal era, na época, relativamente barato e tecnicamente superior
para esse problema — a escolha de ficar em QBasic puro é deliberada, pelo
exercício, não por necessidade).

Ambiente: MS-DOS + QBasic puro (sem `$INCLUDE`, sem módulos carregáveis —
esses recursos só existiam no QuickBasic pago). Modularização feita via
SUBs/FUNCTIONs e, quando o programa cresce demais para a memória, via `CHAIN`
com variáveis `COMMON SHARED` entre programas encadeados.

Escopo funcional: cadastro de clientes, cadastro de produtos, registro de
vendas, relatórios mensais de vendas por produto, por cliente e por dia.

Porte alvo: alguns milhares de produtos, algumas centenas de clientes.

## Decisões de arquitetura de dados

### Cadastros (clientes, produtos)
- Armazenados em arquivos de acesso **randômico** (`RANDOM`), registro de
  tamanho fixo (`TYPE...END TYPE`, `GET`/`PUT`).
- Indexados por **árvores binárias simples** (não B-trees/B+trees — decisão
  consciente de manter simples), também persistidas em arquivos randômicos
  (um arquivo de índice por chave de busca).
- Pode haver múltiplos índices por entidade (ex.: cliente por nome, cliente
  por código; produto por nome, produto por código).
- Chaves normalizadas para comparação uniforme: strings de tamanho fixo
  (nomes truncados/paddados; códigos numéricos com zero à esquerda), o que
  permite que a lógica de busca/inserção da árvore seja a mesma
  independentemente do tipo de chave.

### Árvore binária em array + arquivo
- Técnica clássica (originalmente vista em livro dos anos 80 sobre BASIC com
  linhas numeradas): os nós de **topo** da árvore ficam carregados num
  **array em memória** (cache quente, para consultas rápidas sem I/O), e o
  restante da árvore vive no **arquivo randômico** em disco, endereçado por
  RRN (relative record number) como se fosse um ponteiro manual.
- É, na prática, uma emulação manual de alocação dinâmica/heap (que o QBasic
  não tem) usando o disco como "heap" e o array como cache de tamanho fixo.

### Vendas
- Armazenadas em **arquivos sequenciais, um por mês**, já **denormalizados**
  (gravando dados de cliente, produto etc. diretamente no registro de venda,
  sem precisar buscar as referências depois).

### Relatórios
- Gerados por **external sort** sobre os arquivos de vendas do mês, para
  ordenar e agrupar (por produto, por cliente, por dia).
- Os agregados mensais resultantes são salvos; agregar o ano é apenas somar
  os agregados dos 12 meses já calculados (sem reprocessar o detalhe).

### Reindexação periódica
- Necessária porque exclusões lógicas (registros marcados como deletados)
  vão desbalanceando a árvore ao longo do tempo.
- Processo: gerar um **dump ordenado** do índice via external sort
  (descartando os excluídos), e a partir dele **reconstruir a árvore
  perfeitamente balanceada por bisseção recursiva** (pega o elemento do meio
  do dump como raiz, recursivamente aplica para as metades esquerda/direita).
- Gatilho sugerido: contar exclusões desde a última reindexação num campo de
  cabeçalho do arquivo de índice, disparando quando a razão exclusões/total
  passar de um limiar (ex.: 20–25%).
- Otimização de I/O na reconstrução: se o dump cabe em memória, carregar
  tudo de uma vez (leitura sequencial), fazer a bisseção em memória, e
  escrever o resultado final numa única passada sequencial (montar o array
  de destino em memória antes de gravar, para não gravar na ordem bagunçada
  da recursão). Se não cabe, usar um híbrido: seeks diretos (baratos, porque
  registro é de tamanho fixo) só para os primeiros níveis da árvore, e a
  partir de um certo tamanho de sub-faixa, ler o bloco inteiro contíguo de
  uma vez para processar em memória.
- Uso de índices vs. lote: índices servem para **busca pontual** (ex.: no
  momento da venda); todo processamento em lote (relatórios, reindexação)
  passa por **external sort**, evitando acesso randômico espalhado.

## Duplicação de código e como mitigar

- Sem `$INCLUDE`/units, a árvore binária (e os algoritmos de external sort e
  rebalanceamento) precisam ser **replicados manualmente** em cada módulo
  que usa uma estrutura de dados diferente (cliente por nome, cliente por
  código, produto por nome, produto por código etc.).
- Decisão: **aceitar a duplicação** deliberadamente, em vez de investir em
  geração de código ou abstração via `CHAIN`/templates textuais — já foi
  tentada uma abordagem de concatenação de fontes ("compilação" por
  concatenação) no passado e considerada exaustiva e difícil de debugar (só
  dá para debugar a versão "compilada", não os fontes separados).
- Estratégia de mitigação escolhida (leve, sem ferramenta): **nomear cada
  algoritmo com um comentário no código** (ex.: `' ALGORITMO: busca em
  arvore binaria por chave string`) em cada ocorrência, mais um **índice em
  arquivo .txt** listando os arquivos/linhas onde cada algoritmo nomeado
  aparece — assim, ao corrigir um bug numa cópia, dá para localizar as
  demais cópias que precisam da mesma correção.

## Padrão geral do projeto

Todas as estruturas principais seguem o mesmo padrão de "processar em
blocos, fazer spill para o disco quando o bloco fecha, e consolidar depois":

| Componente | Bloco em memória | Spill | Consolidação |
|---|---|---|---|
| Árvore | Nós de topo em array | Resto no arquivo | Reindexação por bisseção |
| External sort | Runs que cabem em memória | Runs gravadas em disco | Merge das runs |
| Relatórios | Agregado do mês | Agregado mensal salvo | Soma dos agregados = ano |

## Plano de trabalho / próximos passos

Abordagem por **protótipos isolados**, testados no emulador (DOSBox e/ou
pcjs.org, que emula 5150/XT/286/386 — este último é útil especificamente
para medir tempo real de external sort e reindexação em hardware de época),
documentando os procedimentos/algoritmos que funcionam antes de integrá-los
ao sistema final. Ordem sugerida:

1. Layout de registro + leitura/gravação randômica básica (`TYPE`,
   `GET`/`PUT`) — validar antes de complicar com árvore.
2. Cadastro e busca (árvore binária genérica por chave-string).
3. External sort.
4. Agregação (relatórios mensais/anuais).
5. Reindexação (rebalanceamento por bisseção).
