# Reindexação periódica

* Necessária porque exclusões lógicas (registros marcados como
  deletados) desbalanceiam a árvore ao longo do tempo

## Processo

1. Gerar um **dump ordenado** do índice via external sort (descartando os
   excluídos).
2. A partir dele, **reconstruir a árvore perfeitamente balanceada por
   bisseção recursiva**: pega o elemento do meio do dump como raiz,
   recursivamente aplica para as metades esquerda/direita.

## Gatilho sugerido

Contar exclusões desde a última reindexação num campo de cabeçalho do
arquivo de índice, disparando quando a razão exclusões/total passar de um
limiar (ex.: 20–25%).

## Otimização de I/O na reconstrução

**Validado empiricamente** (não só no papel): `testes/REINDEX1.BAS`,
2026-08-15, reconstrução real no `QBASIC.EXE` com buffers pequenos de
propósito (100 registros) sobre 1000 registros — 8/8 verificações OK
(numeração em largura, ordem, profundidade, I/O). Números e detalhe em
[[decisoes]].

- **Numeração de RRN em largura** (sequência de heap: nível 0 = RRN 1,
  nível `k` = RRN `[2^k, 2^(k+1))`) — necessária porque o cache em RAM
  espelha os *primeiros RRN do arquivo*, não a árvore; só largura
  garante que esse prefixo seja o topo real (os dois galhos), não um
  mergulho torto de um lado só. Exige **fila explícita** de faixas
  pendentes (RRN atribuído na hora de enfileirar, mesmo mecanismo de
  "próxima posição livre" da inserção normal) — não existe fórmula
  fechada equivalente (tentativa de aritmética pura testada e
  descartada). Motivo completo, e por que pré-ordem foi descartado:
  [[decisoes]] (2026-08-15)
- **Consequência direta**: a carga do índice pro cache na inicialização
  (`AbreIndiceCliente`/`AbreIndiceProduto`, já implementada,
  [[duplicacoes]]) é só uma leitura sequencial dos primeiros RRN do
  arquivo até encher o cache — sem mudar nada nessa rotina, ela passa a
  carregar o topo de verdade assim que a reindexação numera em largura.
  **A garantia de "sem buraco" é degrau exponencial de N (511, 1023,
  2047, 4095, 8191...), não de K** — usar a capacidade máxima do array
  (K=5041 produtos, ~500 clientes) nunca piora a garantia, só soma uma
  faixa de ganho não-determinístico acima dela. Detalhe, números e o
  trade-off (algoritmo simples vs. garantia permanente de B+Tree):
  [[decisoes]] (2026-08-15)
- **Leitura do dump**: seek direto pro meio da faixa em cada nível
  (barato, registro de tamanho fixo) até a sub-faixa caber no buffer de
  entrada — daí em diante, 1 seek + leitura sequencial do bloco inteiro
- **Escrita: buffer de saída é obrigatório, não otimização opcional** —
  sem ele, leitura (dump) e escrita (saída) intercalam registro a
  registro; disparar rajada de gravação sequencial em vez de intercalar
  nunca é pior, independente de configuração do MS-DOS (monotarefa,
  executa exatamente a sequência de chamadas emitida pela aplicação, sem
  reordenar). Acumula nós do topo num buffer em memória; ao fechar um
  nível (faixa contígua de RRN em numeração de largura), 1 seek +
  gravação sequencial do buffer inteiro
- **Atalho "faixa cabe no buffer, resolve tudo de uma vez" precisa
  respeitar fronteira de nível** — não pode disparar só por tamanho, ou
  numera/grava um pedaço fora de ordem enquanto sub-árvores irmãs do
  mesmo nível ainda estão pendentes na fila, furando a garantia "nível
  completo antes de avançar". Só liberar depois que a faixa relevante
  pro cache já foi processada nível a nível — desenho ainda não
  fechado, avaliar no protótipo

## Índices vs. lote

Índices servem para **busca pontual** (ex.: no momento da venda); todo
processamento em lote (relatórios, reindexação) passa por **external
sort**, evitando acesso randômico espalhado.

## Relação com o risco de degeneração do índice

* Não se aplica com a arquitetura atual (ponteiros explícitos, ver
  [[decisoes]]) — só seria mitigação **necessária** (não só otimização)
  contra crescimento explosivo de RRN se o índice usasse endereçamento
  implícito, opção descartada (ver [[armadilhas]])
