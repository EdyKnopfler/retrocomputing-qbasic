# Regras de negócio

## Cliente padrão "Consumidor" (ID 0)

A maioria das vendas não identifica o cliente. Usa-se um cliente fixo,
**ID 0, "Consumidor"**, que **não existe como registro no cadastro** (não é
uma entrada real na árvore de clientes — é um caso especial tratado em
código).

O CPF é informado **ocasionalmente**: quando o cliente quer algum benefício
fiscal (nota fiscal com CPF) ou da própria loja (desconto, fidelidade).

**Implicação técnica:** o fluxo de venda deve ter um atalho para ID 0 que
evita completamente a busca na árvore de clientes. A busca no índice de
clientes só acontece quando um CPF é de fato informado — esse é o caminho
raro, não o comum. Ver [[armadilhas]] e [[arquitetura-tecnica]] para como
isso afeta o dimensionamento do índice de clientes (pode ficar pequeno,
cabe inteiro em RAM).

## Produto via leitor de código de barras

Produtos são majoritariamente identificados por leitura de código de
barras, não digitação manual do código. Isso reforça o código de barras
como chave de busca natural e principal do índice de produtos (ver
[[arquitetura-tecnica]]).

## Porte alvo

- Produtos: algumas milhares de unidades cadastradas.
- Clientes: algumas centenas de unidades cadastradas.
- Por venda: tipicamente 1 busca de cliente (opcional, só se CPF for
  informado) + 1 busca de produto por item vendido.
