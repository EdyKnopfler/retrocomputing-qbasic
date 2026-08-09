# Plano de trabalho / próximos passos

* Abordagem por **protótipos isolados**, testados no emulador (DOSBox
  e/ou pcjs.org — este último emula 5150/XT/286/386, útil pra medir
  tempo real de external sort/reindexação em hardware de época),
  documentados antes de integrar ao sistema final

## Ordem sugerida

1. Layout de registro + leitura/gravação randômica básica (`TYPE`,
   `GET`/`PUT`) — validar antes de complicar com árvore.
2. Cadastro e busca (árvore binária genérica por chave-string).
3. External sort.
4. Agregação (relatórios mensais/anuais).
5. Reindexação (rebalanceamento por bisseção).

## Ferramentas e ambiente de teste

* Tudo roda no DOSBox, `C:\` montado em `~/Documentos/DOS` (`mount c
  ~/Documentos/DOS` em `[autoexec]` de `~/.dosbox/dosbox-0.74-3.conf`)
* `C:\SISTEMA\TESTES\` = protótipos. `C:\QBASIC\QBASIC.EXE` = QBasic
  gratuito, o único interpretador usado — é o alvo real do exercício
* **`QBASIC.EXE`** trava num diálogo modal em qualquer erro de
  sintaxe/runtime — fatal pra script headless. Mitigar com `ON ERROR
  GOTO` global + gravação em arquivo (ver "Executar provas em QBasic"
  abaixo)
* **Limite de nome 8.3 do DOS** — 8 caracteres antes do ponto, 3
  depois. Fora disso falha silencioso (arquivo não é criado/achado, sem
  erro)

### Executar provas em QBasic (sem travar, sem tela)

* `ON ERROR GOTO <rótulo>` no programa principal (nunca dentro de
  SUB/FUNCTION — ver [[armadilhas]]); no bloco de tratamento, gravar
  `ERR` e `ERL`
* Não usar `PRINT` pra resultado — gravar em arquivo (`OPEN ... FOR
  OUTPUT`), fechar antes de terminar
* `PRINT #n` (arquivo) **não é visível em tempo real** — testado
  empiricamente (`FLUSH.BAS`, 2026-08-09): o QBasic só grava o
  conteúdo no `CLOSE`, mesmo com `SLEEP` entre os `PRINT #n`. Não dá
  pra acompanhar progresso de uma rodada longa lendo o arquivo enquanto
  ela roda — só depois que termina
* `PRINT` na tela (sem `#`) é o único jeito de ver progresso ao vivo
  (ex.: um `.` a cada N linhas processadas) — sem isso, uma rodada
  longa parece travada mesmo estando viva
* Rodar via `dosbox -conf ~/.dosbox/dosbox-0.74-3.conf -c "C:" -c "CD
  SISTEMA\TESTES" -c "..\..\QBASIC\QBASIC.EXE /RUN ARQUIVO.BAS" -c
  "EXIT"`, sempre dentro de `timeout` no shell
* Se o `timeout` não matar o DOSBox (acontece — ele ignora SIGTERM
  parado num modal), `kill -9` direto no PID
* Ler o arquivo de saída depois que o DOSBox sai/é morto

**Referência de linguagem:** [manual do QBasic 1.1 em
qbasic.net](https://qbasic.net/en/qb-manual/qb11/overview.htm) —
material sobre QBasic é escasso, consultar o manual antes de assumir
que uma sintaxe/função é válida.

## Estado atual

* Medição de memória disponível feita (`SISTEMA.BAS`) — ver [[decisoes]]
* Passo 2 (árvore binária genérica por chave-string, com backing em
  arquivo) prototipado e validado em `testes/ARVDISCO.BAS`, rodando de
  verdade no `QBASIC.EXE` (não só compilado):
  * 10.000 linhas de CSV, 1.899 chaves distintas inseridas, 8.101
    duplicatas detectadas corretamente
  * Buscas de verificação corretas (raiz via cache, nó profundo via
    arquivo, chave inexistente não encontrada)
  * Persistência confirmada: segunda execução sem apagar o `.IDX`
    retomou `proxRRNLivre`/`raizRRN` do cabeçalho e tratou as 10.000
    linhas como duplicatas
  * Representa o caso de índice **secundário** (com `dadoRRN`
    explícito); índice primário autoindexado fica pra outro protótipo
* Passos 3-5 (external sort, agregação, reindexação) ainda não
  prototipados
* Pontapé inicial do sistema real (não protótipo isolado) feito:
  `SISTEMA.BAS` (menu + carga dos índices primários de cliente/produto
  em `COMMON SHARED`) e `CLIENTES.BAS` (placeholder: mostra contagem
  vinda do índice compartilhado, `CHAIN` de volta)
  * Fluxo testado de verdade no `QBASIC.EXE` (harness automatizado com
    sentinela + confirmação interativa do usuário), 2026-08-09
  * Índice primário ainda é só esqueleto de navegação (chave/esquerda/
    direita) — layout de negócio (nome, endereço etc.) fica pra quando
    o cadastro completo entrar
* Decisão de conteúdo do nó (ponteiros explícitos vs. implícitos): já
  fechada — ver [[decisoes]] e [[armadilhas]]
