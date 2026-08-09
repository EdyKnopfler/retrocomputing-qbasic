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
