# Índice de código duplicado

Ver [`arquitetura-tecnica.md`](arquitetura-tecnica.md#duplicação-de-código).

Toda ocorrência de código nomeado como repetido (comentário `' REPETICAO:
...`) fica listada aqui — nome, propósito de uma linha, e cada arquivo/SUB
onde aparece — pra achar todas as cópias quando uma precisar de correção.
Cobre qualquer duplicação forçada pela falta de `$INCLUDE`, não só
algoritmo (ex.: layout de `TYPE` replicado entre cadastros).

## Carga do índice primário (árvore binária autoindexada) do arquivo para cache SoA em RAM

Baseado no `AbreIndice` de `testes/ARVDISCO.BAS` (índice secundário, com
`dadoRRN`), adaptado pro caso primário/autoindexado (sem `dadoRRN`).

- `SISTEMA.BAS`, `SUB AbreIndiceCliente`
- `SISTEMA.BAS`, `SUB AbreIndiceProduto`

## Operações de árvore binária (busca, insere/reativa, marca removido, le/grava nó)

Mesmo algoritmo, chave diferente por cadastro (CPF pro cliente, código
de barras pro produto). Origem: `testes/CADCLI1.BAS`/`testes/
CADCLI3.BAS` (protótipos que validaram o desenho), portado primeiro pra
`CLIENTES.BAS` e depois replicado pra `PRODUTOS.BAS`. Cópias headless
descartáveis em `testes/CLIVAL1.BAS` (cliente) e `testes/PRDVAL1.BAS`
(produto, cobre só o que muda: campo `SINGLE` do preço).

- `CLIENTES.BAS`, `SUB BuscaCliente` / `PRODUTOS.BAS`, `SUB BuscaProduto`
- `CLIENTES.BAS`, `SUB InsereOuReativaCliente` / `PRODUTOS.BAS`, `SUB InsereOuReativaProduto`
- `CLIENTES.BAS`, `SUB MarcaRemovidoCliente` / `PRODUTOS.BAS`, `SUB MarcaRemovidoProduto`
- `CLIENTES.BAS`, `SUB LeNoNavCliente` / `PRODUTOS.BAS`, `SUB LeNoNavProduto`
- `CLIENTES.BAS`, `SUB CarregaRegistroCliente` / `PRODUTOS.BAS`, `SUB CarregaRegistroProduto`
- `CLIENTES.BAS`, `SUB GravaRegistroCliente` / `PRODUTOS.BAS`, `SUB GravaRegistroProduto`
- `CLIENTES.BAS`, `FUNCTION ChaveFixaCPF$` / `PRODUTOS.BAS`, `FUNCTION ChaveFixaBarras$`

## Layout `TYPE` do nó primário (cliente/produto), replicado por arquivo

Cada módulo que declara `GET`/`PUT`/parâmetros desse `TYPE` precisa da
definição idêntica (sem `$INCLUDE`) — `TYPE` tem que vir antes de
qualquer `DECLARE` que o use (ver [[armadilhas]]). Os arrays de cache
em `COMMON SHARED` são `STRING`/`LONG` soltos (não do `TYPE`), então só
o módulo que de fato usa `GET`/`PUT` naquele arquivo precisa do `TYPE`.

- `TYPE NoClientePrimario`: `SISTEMA.BAS`, `CLIENTES.BAS`
- `TYPE NoProdutoPrimario`: `SISTEMA.BAS`, `PRODUTOS.BAS`

## Bloco `CONST`/`COMMON SHARED` do topo de árvore

Motivo é diferente do resto deste índice: não é duplicação "por chave"
(a lógica não muda de arquivo pra arquivo) — os valores são idênticos
em todo lugar, forçados a se repetir só porque `COMMON SHARED` casa por
**posição**, não por nome (ver [[armadilhas]]): todo módulo da corrente
de `CHAIN` precisa da MESMA sequência de declaração, mesmo não usando a
variável. Com `$INCLUDE` seria um único arquivo compartilhado, sem
nenhuma parametrização — ao contrário das SUBs de árvore acima, que
mudam de assinatura por chave e continuariam duplicadas mesmo com
`$INCLUDE` (só um genérico de verdade, que QBasic não tem, resolveria).

Assimetria desde 2026-08-15 (arrays de cache viraram dinâmicos — ver
[[decisoes]]): só `SISTEMA.BAS` tem `REDIM` (dimensiona, 1x, dentro do
guarda `indicesCarregados = 0`); `CLIENTES.BAS`/`PRODUTOS.BAS` têm só a
declaração `COMMON SHARED`, sem `DIM` nem `REDIM` — `REDIM` de novo
zeraria o cache já populado.

- `CONST tamChaveCliente%` até `RRNULTIMOCACHEProduto&`: `SISTEMA.BAS`,
  `CLIENTES.BAS`, `PRODUTOS.BAS` (`ESQUERDO%`/`DIREITO%` só em
  `CLIENTES.BAS`/`PRODUTOS.BAS` — `SISTEMA.BAS` só carrega o cache, não
  percorre a árvore). Valores atuais: `capacidadeCacheCliente% = 511`,
  `capacidadeCacheProduto% = 5041` (ver [[decisoes]])
- `REDIM cacheClienteChave/Esq/Dir`, `cacheProdutoChave/Esq/Dir`: só
  `SISTEMA.BAS`, dentro do guarda `indicesCarregados = 0`
- `COMMON SHARED` (contadores `proxRRNLivre*`/`qtdInseridos*`/
  `qtdExcluidos*`, arrays de cache, `indicesCarregados`):
  `SISTEMA.BAS`, `CLIENTES.BAS`, `PRODUTOS.BAS`
