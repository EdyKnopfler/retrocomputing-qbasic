# Regras de negócio

## Cliente padrão "Consumidor" (ID 0)

* Maioria das vendas não identifica cliente — usa-se **ID 0,
  "Consumidor"**, que **não existe como registro no cadastro** (caso
  especial em código, não entrada na árvore)
* CPF informado só **ocasionalmente** (benefício fiscal ou da loja)
* **Implicação técnica:** fluxo de venda tem atalho pro ID 0 que evita
  a busca na árvore; busca no índice só acontece quando CPF é informado
  (caminho raro). Afeta dimensionamento do índice — ver [[armadilhas]] e
  [[arquitetura-tecnica]]

## Produto via leitor de código de barras

* Produto é majoritariamente identificado por leitura de código de
  barras, não digitação — reforça código de barras como chave principal
  do índice de produtos (ver [[arquitetura-tecnica]])

## Porte alvo

- Produtos: algumas milhares de unidades cadastradas.
- Clientes: algumas centenas de unidades cadastradas.
- Por venda: tipicamente 1 busca de cliente (opcional, só se CPF for
  informado) + 1 busca de produto por item vendido.
