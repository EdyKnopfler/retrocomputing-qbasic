# Plano de trabalho / próximos passos

Abordagem por **protótipos isolados**, testados no emulador (DOSBox e/ou
pcjs.org, que emula 5150/XT/286/386 — este último é útil especificamente
para medir tempo real de external sort e reindexação em hardware de
época), documentando os procedimentos/algoritmos que funcionam antes de
integrá-los ao sistema final.

## Ordem sugerida

1. Layout de registro + leitura/gravação randômica básica (`TYPE`,
   `GET`/`PUT`) — validar antes de complicar com árvore.
2. Cadastro e busca (árvore binária genérica por chave-string).
3. External sort.
4. Agregação (relatórios mensais/anuais).
5. Reindexação (rebalanceamento por bisseção).

## Estado atual

- Medição de memória disponível feita (`SISTEMA.BAS`) — ver
  [[decisoes]].
- Ainda nenhum protótipo do passo 1 em diante implementado.
- Decisão pendente antes do passo 2: conteúdo do nó do índice (ponteiros
  explícitos vs. implícitos) — ver [[decisoes]].
