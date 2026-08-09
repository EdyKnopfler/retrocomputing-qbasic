# Índice de algoritmos duplicados

Ver [CLAUDE.md](../CLAUDE.md), seção "Duplicação de código".

Cada ocorrencia de um algoritmo nomeado no codigo (comentario "ALGORITMO: ...")
esta listada aqui, pra facilitar achar todas as copias quando uma delas
precisar de correcao.

## Carga do indice primario (arvore binaria autoindexada) do arquivo
## para cache SoA em RAM

Baseado no AbreIndice de testes/ARVDISCO.BAS (indice secundario, com
dadoRRN), adaptado para o caso primario/autoindexado (sem dadoRRN).

- SISTEMA.BAS, SUB AbreIndiceCliente
- SISTEMA.BAS, SUB AbreIndiceProduto
