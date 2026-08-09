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

## Documentação

Detalhes vivem em [`docs/`](docs/), organizados por tema — este arquivo é só
o resumo essencial:

- [`docs/regras-de-negocio.md`](docs/regras-de-negocio.md) — cliente padrão
  "Consumidor" (ID 0), CPF opcional, produto via leitor de código de barras,
  porte alvo.
- [`docs/arquitetura-tecnica.md`](docs/arquitetura-tecnica.md) — cadastros
  randômicos, árvore binária em array+arquivo, índices (CPF/código de
  barras), orçamento de memória, limite de 64KB/array, `CHAIN`+`COMMON
  SHARED`, vendas, relatórios, duplicação de código.
- [`docs/reindexacao.md`](docs/reindexacao.md) — rebalanceamento por
  bisseção, gatilho de reindexação, otimização de I/O.
- [`docs/decisoes.md`](docs/decisoes.md) — log cronológico de decisões de
  arquitetura, incluindo o que está confirmado e o que está em aberto.
- [`docs/armadilhas.md`](docs/armadilhas.md) — gotchas específicos do
  QBasic/da arquitetura (armadilha de `COMMON` posicional, limite de
  array, risco de degeneração de índice, etc.).
- [`docs/plano-de-trabalho.md`](docs/plano-de-trabalho.md) — roteiro de
  protótipos isolados e estado atual.

## Resumo essencial

- **Dados:** cadastros em arquivo randômico (`TYPE`/`GET`/`PUT`) + índice
  em árvore binária (topo em array `COMMON SHARED`, resto em arquivo,
  endereçado por RRN). Vendas em arquivo sequencial mensal denormalizado.
  Relatórios via external sort; agregados mensais somados para o ano.
- **Índices desta aplicação:** cliente por CPF, produto por código de
  barras. Cliente "Consumidor" (ID 0) não existe no cadastro — é caso
  especial.
- **Memória medida** (`PRINT FRE(-1), FRE(-2), FRE("")`): 157972B estática,
  1052B stack, 30884B strings. Teto de 65536B por array individual
  (limite de segmento do QBasic).
- **Decisão em aberto:** conteúdo estrutural do nó do índice — ponteiros
  explícitos (esquerda/direita) vs. endereçamento implícito/posicional.
  Ver [`docs/decisoes.md`](docs/decisoes.md).
- **Duplicação de código é aceita** entre cópias do algoritmo de árvore
  para cada chave diferente, mitigada por comentário nomeado + índice em
  .txt — não por geração/concatenação de código (já tentado, descartado).
