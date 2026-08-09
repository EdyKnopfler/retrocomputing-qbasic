# Armadilhas / gotchas conhecidos

Lista de coisas fáceis de errar por serem específicas do QBasic ou da
arquitetura escolhida, não óbvias a partir do código.

## `COMMON`/`COMMON SHARED` casa por posição, não por nome

Ao encadear módulos via `CHAIN`, o QBasic casa as variáveis de `COMMON`
**pela ordem de declaração e pelo tipo**, não pelo nome da variável. Se um
módulo no meio da corrente declarar o bloco em ordem diferente, ou
esquecer uma variável (mesmo uma que ele não use), os dados dos topos de
árvore se desalinham silenciosamente — sem erro, só dado errado.

**Regra:** todo módulo que participa da corrente de `CHAIN` replica a
declaração `COMMON SHARED` idêntica, na mesma ordem, mesmo que não use
todas as variáveis compartilhadas.

## Limite de 64KB por array

QBasic não suporta "huge arrays" (isso só existe no BASIC PDS com
`/AH`). Um único array `DIM`'d não pode passar de 65536 bytes — limite de
segmento, independente do orçamento total de memória estática disponível.
Ver cálculo de capacidade em [[arquitetura-tecnica]].

## Risco de degeneração sob endereçamento implícito (posicional)

Se os nós da árvore forem endereçados de forma implícita (filho esquerdo
de `n` em `n*2`, direito em `n*2+1`, sem campos de ponteiro próprios),
inserção de chaves em sequência crescente (ex.: código de barras
cadastrado em lote, em ordem do fornecedor) degenera a árvore numa
corrente quase linear — e a posição de cada nó nessa corrente **dobra a
cada nível**. Poucas dezenas de inserções nessa ordem já geram RRN muito
acima de qualquer limite prático de array ou arquivo, mesmo com poucos
nós reais cadastrados.

**Status: confirmado e descartado** — evidência empírica em
`/home/ederson/Documentos/DOS/projeto/testes/teste3.bas`, que tentou essa
fórmula posicional e precisou de 10x o espaço (`nChaves * 10`) pra
sobreviver a 800 chaves reais sem estourar o array. Decisão final: usar
ponteiros explícitos (esquerda/direita como campos `LONG` próprios) — ver
[[decisoes]] e [[arquitetura-tecnica]]. Esta seção fica mantida como
registro histórico do porquê a alternativa foi descartada, pra não
repetir o erro depois.

## Convenção de nó zerado exige write-through

A regra "RRN pequeno → olha o array em RAM; RRN grande → busca no
arquivo; RRN zero → não existe nó" só funciona se o array em RAM for
espelho exato dos primeiros N registros do arquivo de índice. Qualquer
inserção/atualização cujo RRN caia dentro da faixa cacheada precisa
gravar nos dois lugares (array E arquivo). Esquecer isso quebra a busca
silenciosamente — a busca vai continuar "achando" a versão antiga no
array.

## Arquivos-fonte `.BAS`: só ASCII puro, com CRLF

* Sem acento/caractere fora de `0x00-0x7F` — um só já corrompeu o parser
  do editor DOS (linhas se fundiram visualmente, erro de sintaxe num
  ponto sem relação aparente com o acento)
* Terminador de linha CRLF, não LF
* Checar fora do DOS: `file arquivo.BAS` deve dizer "ASCII text, with
  CRLF line terminators"

## `DIR$` não existe neste dialeto

Idiomatismo de Visual Basic, não de QBasic/QuickBASIC. Pra checar se um
arquivo existe antes de um `OPEN ... FOR RANDOM` (que cria o arquivo se
não existir): `ON ERROR GOTO` + `OPEN ... FOR INPUT` (erro = não
existe), ou `LOF(1) = 0` depois de abrir em modo RANDOM. Confirmado
funcionando em `testes/ARVDISCO.BAS`, rodado de verdade no `QBASIC.EXE`.

## `ON ERROR GOTO <rótulo>` só vale no programa principal

* Rótulo não pode ficar dentro de `SUB`/`FUNCTION` — diferente de
  Visual Basic
* Pra decidir algo (ex.: "arquivo já existe?") dentro de uma rotina
  chamada por uma SUB: resolver no programa principal, antes da
  chamada, guardando o resultado numa `SHARED` que a SUB só lê
* Confirmado pelo usuário em 2026-08-08, depois de eu colocar o rótulo
  dentro de `SUB AbreIndice` em `ARVDISCO.BAS` por engano

## Cliente "Consumidor" (ID 0) não é um registro real

Não tentar buscar ID 0 na árvore de clientes — ele não existe lá por
design (ver [[regras-de-negocio]]). O fluxo de venda precisa tratar esse
ID como caso especial antes de qualquer busca de índice.
