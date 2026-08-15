# Indo ao limite com estruturas de dados

Escrevendo "na mão" aqui, diferentemente das docs que são atualizadas pelo Claude. Podem árvores binárias simples indexar dados em um sistema dos anos 80?

A resposta é que sim, mas existem limitações. O trade-off aqui é a simplicidade do código vs. ganho de eficiência.

Fazemos cache do topo da árvore, além de reindexação para rebalanceamento (feature em andamento). No entanto, a natureza da linguagem (que exige codar árvores usando arrays) e os limites de memória nos obrigam a encarar algumas restrições impostas pela própria matemática, como pode ser conferido na documentação sobre a [reindexação](docs/reindexacao.md) e no [log de decisões](docs/decisoes.md) (regiões "perigosas" onde a garantia de cache não cobre).

`<escrito pelo Gemini>`A propriedade do heap estrito (_2i_ e _2i+1_) só funciona de forma perfeita e sem buracos quando a árvore é estritamente completa (_N = 2^k - 1_).`</escrito pelo Gemini>` O que foi feito: dividir a memória alocável entre os índices de tal forma que cada um completasse um nível, mais um pouquinho só para aproveitar espaço. Cache hit ali na sobra é lucro.

O benchmark vai ser o 286 emulado em [PCjs Machines](https://www.pcjs.org/). Em outro momento tentarei implementar B+Trees com ajuda da IA.