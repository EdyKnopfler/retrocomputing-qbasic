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

- Se o dump cabe em memória: carregar tudo de uma vez (leitura
  sequencial), fazer a bisseção em memória, e escrever o resultado final
  numa única passada sequencial (montar o array de destino em memória
  antes de gravar, para não gravar na ordem bagunçada da recursão).
- Se não cabe: usar um híbrido — seeks diretos (baratos, porque registro
  é de tamanho fixo) só para os primeiros níveis da árvore, e a partir de
  um certo tamanho de sub-faixa, ler o bloco inteiro contíguo de uma vez
  para processar em memória.

## Índices vs. lote

Índices servem para **busca pontual** (ex.: no momento da venda); todo
processamento em lote (relatórios, reindexação) passa por **external
sort**, evitando acesso randômico espalhado.

## Relação com o risco de degeneração do índice

* Não se aplica com a arquitetura atual (ponteiros explícitos, ver
  [[decisoes]]) — só seria mitigação **necessária** (não só otimização)
  contra crescimento explosivo de RRN se o índice usasse endereçamento
  implícito, opção descartada (ver [[armadilhas]])
