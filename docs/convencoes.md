# Convenções

## Escrita de documentação (`docs/*.md` e `CLAUDE.md`)

* Bullet curto e imperativo, não prosa corrida — "faça assim, não faça
  assado". Abuse de sub-bullets em vez de frases coordenadas
* Justificativa: no máximo uma cláusula curta — só quando o motivo não
  é óbvio ou muda quando a regra vale/não vale. Nunca um parágrafo
* Cada fato/decisão tem **um lugar canônico**; os demais arquivos
  linkam (`[[nome]]`) em vez de repetir o racional/evidência inteiros
  * `decisoes.md` — histórico: decisão + motivo + evidência (arquivo de
    teste, números de carga)
  * `arquitetura-tecnica.md` — estado atual (o quê, não o porquê); link
    pra `decisoes.md` quando o racional for necessário
  * `armadilhas.md` — só efeito prático do erro + como evitar, sem
    repetir o racional de arquitetura já registrado em `decisoes.md`
* Não narrar o processo de deliberação (cogitado → testado →
  descartado) fora de `decisoes.md` — os outros arquivos citam só a
  conclusão

## Código (arquivos de produção)

Regras de estilo pro código "de verdade" do sistema — **não** pros
protótipos isolados em `testes/`, que podem ser escritos de qualquer
jeito. Fonte: `/home/ederson/Documentos/DOS/projeto/testes/teste.bas`,
apontado pelo usuário em 2026-08-09 como referência de convenção. Lista
cresce conforme o usuário for indicando mais.

### Indentação

* Código executável do programa principal (fora de qualquer
  SUB/FUNCTION) é indentado 2 espaços, mesmo não estando dentro de um
  bloco — só `DECLARE`/`CONST`/`DIM SHARED` no topo e **rótulos**
  (`Rotulo:`) ficam na coluna 0
* Dentro de SUB/FUNCTION: corpo indentado 2 espaços a partir do
  cabeçalho; cada bloco aninhado (`DO`/`FOR`/`IF`) soma mais 2 espaços
* Exemplo (`teste.bas`):
  ```basic
    ON ERROR GOTO TmpExiste
    MKDIR "c:\projeto\tmp"
  TratouTmp:
    ON ERROR GOTO 0

    OPEN "c:\projeto\vendas1.csv" FOR INPUT AS #1
  ```

### Tratamento de erro

* `ON ERROR GOTO <rótulo>` logo antes da operação arriscada; o rótulo
  de continuação vem logo depois da operação, ainda no fluxo principal
* O handler em si fica separado do fluxo principal — no fim do
  programa, depois do `END`/`SYSTEM`, antes das SUBs/FUNCTIONs — pra
  não interromper visualmente o caminho feliz
* Dentro do handler: resolve o problema, depois `RESUME <rótulo de
  continuação>` pra voltar ao fluxo principal
* Handler pode ter `ON ERROR GOTO` aninhado, se a própria recuperação
  puder falhar (ex.: `KILL` que erra se não achar nada pra apagar) —
  mesmo padrão, `RESUME` pro mesmo ponto de continuação
* Exemplo (`teste.bas`, criar pasta temporária que pode já existir):
  ```basic
    ON ERROR GOTO TmpExiste
    MKDIR "c:\projeto\tmp"
  TratouTmp:
    ON ERROR GOTO 0
    ' ... segue o fluxo principal ...
    END

  TmpExiste:
    ON ERROR GOTO Ignora1
      KILL "c:\projeto\stmp\*.*"
      RESUME TratouTmp
  Ignora1:
      RESUME TratouTmp
  ```
* Lembrete: `ON ERROR GOTO <rótulo>` só vale no programa principal, não
  dentro de SUB/FUNCTION — ver [[armadilhas]]
