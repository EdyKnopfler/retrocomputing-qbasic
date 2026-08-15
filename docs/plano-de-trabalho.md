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
  depois. **Não é sempre silencioso**: violar o limite no argumento do
  `QBASIC.EXE /RUN arquivo.BAS` (nome do próprio `.BAS`) trava num
  diálogo modal "Bad file name" — confirmado ao vivo com
  `testes/SISVALID2.BAS` (9 caracteres antes do ponto), 2026-08-15,
  corrigido renomeando pra `SISVAL2.BAS`. Violar o limite num `OPEN`/
  `KILL` dentro do programa também gera erro trapeável "Bad file name"
  (não "não criado/achado" — ver [[armadilhas]], caso
  `testes/TESTSYS1.BAS`/`NAOEXISTE.XXX`)

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
* **`< arquivo` no `-c` do DOSBox não é redirecionamento de stdin de
  verdade** — o shell do DOSBox faz *stuffing* do buffer de teclado da
  BIOS, limitado a ~15 caracteres. Um `LINE INPUT` isolado e curto
  funciona (confirmado, `testes/TESTIN1.BAS`); um roteiro de tela com
  múltiplos `INPUT`/`LINE INPUT` em sequência (dezenas de linhas) trava
  sem digitar nada, sem erro visível (confirmado tentando validar
  `CLIENTES.BAS` fim-a-fim, 2026-08-15). Não há `xdotool` disponível
  neste ambiente pra simular teclas de verdade na janela. **Tela
  interativa com múltiplos prompts em sequência exige teste manual do
  usuário** — só a lógica por trás (SUBs chamadas direto, sem `INPUT`)
  dá pra validar headless
* `> arquivo` no `-c` do DOSBox **redireciona a saída de tela** (`PRINT`
  sem `#`) de verdade pro arquivo — mas **não usar junto com `<`** na
  mesma chamada: `QBASIC.EXE /RUN X.BAS < IN.TXT > OUT.TXT` quebra o
  modo de vídeo em tela cheia (tela preta, nem o "menu" aparece).
  Confirmado, 2026-08-15

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
    explícito)
* Índice **primário** autoindexado (cliente por CPF, com campos de
  negócio completos) prototipado e validado em `testes/CADCLI1.BAS` +
  `CADCLI2.BAS`, rodando de verdade no `QBASIC.EXE`:
  * Duas fases, dois processos `QBASIC.EXE` separados — fase 1 insere
    em arquivo vazio; fase 2 recarrega o mesmo arquivo do zero (memória
    nova) e continua operando, provando que o topo da árvore volta do
    disco corretamente
  * 34/34 verificações passaram (inserção, rejeição de duplicado ativo,
    busca por CPF existente/inexistente, remoção lógica, reativação de
    CPF removido reaproveitando o RRN, contadores)
  * Fecha a decisão de desenho: sem registro de cabeçalho, raiz sempre
    RRN 1, contadores derivados de `LOF` — ver [[decisoes]]
  * Caminho "nó além do array" validado à parte em `testes/CADCLI3.BAS`
    (cache de propósito minúsculo, 2 nós, igual à técnica do
    `ARVDISCO.BAS`): cadeia de 9 clientes em ordem crescente de CPF
    (pior caso — árvore toda enviesada), busca profunda atravessando 7
    saltos só-em-disco, remoção/reativação de nó fora do cache, e
    inserção de filho novo sob pai fora do cache (ponteiro atualizado
    corretamente no arquivo) — 30/30 verificações OK
* **Passo 3 (external sort): mecanismo genérico (runs + merge k-vias)
  prototipado e validado no `QBASIC.EXE`**, `testes/EXTSORT1.BAS`,
  2026-08-15 — só o algoritmo de ordenação, chave-string genérica, sem
  agregação (passo 4 abaixo) e sem plugar ainda no dump de reindexação
  ou em vendas reais. 31/31 verificações OK em 4 cenários (embaralhado
  com duplicatas, já ordenado, ordem reversa, N menor que 1 buffer).
  Detalhes, números de I/O e o que ficou em aberto (merge
  multi-passada): [[decisoes]]
* Passo 4 (agregação) ainda não prototipado
* **Passo 5 (reindexação): reconstrução por bissecção prototipada e
  validada no `QBASIC.EXE`**, `testes/REINDEX1.BAS`, 2026-08-15 — cobre
  só o passo 2 do processo ([[reindexacao]]; dump gerado já ordenado,
  sem external sort de verdade — isso é o passo 3 acima, prototipado
  separadamente). 8/8 verificações OK, incluindo evidência empírica da
  otimização de I/O (saída sempre sequencial, entrada de 1000 pra 71
  seeks). Detalhes, números e o que ficou em aberto: [[decisoes]]
* Pontapé inicial do sistema real (não protótipo isolado) feito:
  `SISTEMA.BAS` (menu + carga dos índices primários de cliente/produto
  em `COMMON SHARED`) e `CLIENTES.BAS` (placeholder inicial, depois
  substituído pelo cadastro completo — ver bullet abaixo)
  * Fluxo testado de verdade no `QBASIC.EXE` (harness automatizado com
    sentinela + confirmação interativa do usuário), 2026-08-09
* **Cadastro de clientes completo implementado** em `CLIENTES.BAS`
  (busca por CPF, insere, edita, remove logicamente), 2026-08-15:
  * `SISTEMA.BAS` atualizado pro desenho sem cabeçalho (ver
    [[decisoes]]) — `NoClientePrimario` agora carrega o layout de
    negócio completo (antes só esqueleto de navegação)
  * Tela: CPF em branco volta ao menu; achou (ativo) → apresenta +
    `[E]ditar/[R]emover/[V]oltar`; não achou (ou achou removido
    logicamente, tratado como não encontrado) →
    `[I]nserir/[V]oltar`; editar mantém campo em branco = inalterado
    (sem edição nativa no QBasic); remover pede confirmação `[S/N]`;
    toda operação volta direto ao menu ao terminar
  * `LINE INPUT` em vez de `INPUT` em todo campo de texto — `INPUT`
    trata vírgula como separador mesmo com 1 variável só (confirmado
    no manual), quebraria endereço/complemento digitados livremente
  * Lógica de árvore (`BuscaCliente`/`InsereOuReativaCliente`/
    `MarcaRemovidoCliente`/etc.) validada headless (sem a tela) em
    `testes/CLIVAL1.BAS`, 18/18 verificações OK — cobre inserção,
    duplicado ativo rejeitado, busca, edição direta, remoção lógica,
    reativação com mesmo RRN
  * Camada de tela (`LINE INPUT`/`CLS`/fluxo `E`/`R`/`I`/`V`) validada
    manualmente pelo usuário no `QBASIC.EXE` de verdade (não dava pra
    automatizar — ver limitação de teclado em "Ferramentas e ambiente
    de teste" acima), 2026-08-15: aprovado
* **Cadastro de produtos completo implementado** em `PRODUTOS.BAS`
  (busca por código de barras EAN-13, insere, edita, remove
  logicamente), 2026-08-15 — mesmo algoritmo/tela de `CLIENTES.BAS`
  (ver [[duplicacoes]]), só 2 campos de negócio (descrição + preço,
  ambos obrigatórios) em vez de 6:
  * `SISTEMA.BAS` atualizado — `NoProdutoPrimario` ganhou layout de
    negócio completo (antes só esqueleto de navegação)
  * Único elemento novo em relação a `CLIENTES.BAS`: campo `preço`
    (`SINGLE`, primeiro campo numérico do sistema) — lido como texto
    via `LINE INPUT` e convertido com `VAL()` na hora de gravar, pra
    não depender de `INPUT` num campo numérico (que trata Enter em
    branco como erro "Redo from start", incompatível com o padrão
    "Enter mantém" da edição). `VAL("")`/`VAL(texto inválido)` = 0,
    confirmado no manual — usado pra rejeitar preço em branco/inválido
    na inserção
  * Lógica de árvore não foi re-testada (código idêntico ao de
    `CLIENTES.BAS`, já provado) — só o que muda foi checado headless
    em `testes/PRDVAL1.BAS`, 16/16 verificações OK (inclui `SINGLE`
    sobrevivendo ao `GET`/`PUT` com casas decimais)
  * Camada de tela validada manualmente pelo usuário no `QBASIC.EXE` de
    verdade (inserção, busca, edição, remoção e reativação de RRN
    removido, tudo confirmado), 2026-08-15: aprovado
* **Capacidade real dos arrays de cache definida:** 500 clientes / 5041
  produtos (antes: placeholders 50/100 de kickoff), 2026-08-15 — medição
  de `FRE(-1)` revelou que array **estático** (`DIM`) e **dinâmico**
  (`REDIM`) têm tetos diferentes (64KB do DGROUP inteiro vs. 64KB por
  array), forçando a troca das arrays de cache pra dinâmicas. Detalhes:
  [[decisoes]], [[arquitetura-tecnica]], [[armadilhas]]
* Decisão de conteúdo do nó (ponteiros explícitos vs. implícitos): já
  fechada — ver [[decisoes]] e [[armadilhas]]
