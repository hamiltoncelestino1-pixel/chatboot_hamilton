# Task 29 — Fix: `pipeline_stages_controller.rb` voltou para CRLF

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).

## Objetivo

`app/controllers/api/v1/accounts/pipeline_stages_controller.rb` está com terminadores **CRLF** no
working tree, e o rubocop acusa:

```
app/controllers/api/v1/accounts/pipeline_stages_controller.rb:1:1: C: Layout/EndOfLine: Carriage return character detected.
```

O arquivo foi tocado pela [task 01](01-items-count-sem-carregar-cards.md) e estava em LF na
auditoria de 2026-09-16 (o rubocop daquele dia listou as ofensas de `Metrics/*` e
`Rails/SkipsModelValidations` desse arquivo, mas **não** `Layout/EndOfLine`). Ou seja: regrediu em
algum momento entre aquela auditoria e agora.

É a terceira ocorrência do mesmo problema no mesmo ciclo de trabalho — a
[task 22](22-fix-crlf-em-arquivos-ruby.md) corrigiu `macros_controller.rb` e
`macros_pipeline_execution_job.rb` e acrescentou `*.rb text eol=lf` ao `.gitattributes`
justamente para isso parar de acontecer.

**Contexto importante antes de mexer:** 1697 dos 1714 arquivos `.rb` do working tree estão em
CRLF. Isso é o estado normal deste checkout Windows (`core.autocrlf=true`) e **não** é algo que
este trabalho causou — é por isso que rodar `bundle exec rubocop` na árvore inteira sempre
devolveu uma enxurrada de `Layout/EndOfLine` e ninguém reparou. A regra nova do `.gitattributes`
vai normalizar isso para LF no próximo checkout, o que é o comportamento desejado. O escopo desta
task é **só** o arquivo que este trabalho tocou e que deveria ter ficado LF.

## O que corrigir

1. Converter `app/controllers/api/v1/accounts/pipeline_stages_controller.rb` para LF.
2. Confirmar que os outros arquivos tocados por estas tasks continuam em LF —
   `pipeline_item_finder.rb`, `pipeline_items_controller.rb`, `pipelines_controller.rb`,
   `macros_controller.rb`, `macros_pipeline_execution_job.rb`, `pipeline_item.rb`,
   `action_cable_listener.rb` estavam todos LF na auditoria, mas checar de novo na hora de fechar.
3. Verificar se a regra `*.rb text eol=lf` do `.gitattributes` está de fato ativa
   (`git check-attr text eol -- <arquivo>`) — se estiver e o arquivo ainda voltou a CRLF, o
   culpado é uma ferramenta que escreve o arquivo sem passar pelo git, e vale identificar qual
   antes de só converter de novo.

## Fora de escopo (registrar, não corrigir)

As outras 4 ofensas do mesmo arquivo são **pré-existentes** e vivem no `reorder` de stages, que
nenhuma task desta pasta tocou:

```
:35:3: C: Metrics/AbcSize: Assignment Branch Condition size for reorder is too high. [26.94/26]
:35:3: C: Metrics/CyclomaticComplexity: [12/7]
:35:3: C: Metrics/PerceivedComplexity: [12/8]
:46:31: C: Rails/SkipsModelValidations: Avoid using update_column
```

Não misturar um refactor do `reorder` de stages num fix de line ending.

## Testes

- `bundle exec rubocop --force-exclusion app/controllers/api/v1/accounts/pipeline_stages_controller.rb`
  sem `Layout/EndOfLine` (as 4 ofensas pré-existentes continuam — é o esperado).
- `git diff` do arquivo mostra só as linhas reais da task 01.
- `bundle exec rspec spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` continua
  passando (sanidade).

## Critério de pronto

- Arquivo em LF, sem ofensa de `Layout/EndOfLine`.
- Os outros 7 arquivos Ruby tocados por esta pasta reconfirmados em LF.
- Causa da recorrência investigada e registrada aqui (ainda que a conclusão seja "não
  identificada").

## Resultado (2026-09-20)

`pipeline_stages_controller.rb` convertido para LF (`git ls-files --eol`: `i/lf w/lf attr/text eol=lf`).
`git diff` do arquivo mostra só as linhas da task 01 (`@items_counts` em `index`/`show`/`create`/
`update`, +7/-2), sem ruído de line ending. `rubocop --force-exclusion` no arquivo: as 4 ofensas
pré-existentes do `reorder` (`AbcSize`, `CyclomaticComplexity`, `PerceivedComplexity`,
`SkipsModelValidations`) e **nenhum** `Layout/EndOfLine`. `rspec` de `pipeline_items_controller_spec`:
6/6 (não existe spec do controller de stages).

**Os outros arquivos tocados por esta pasta** foram reconferidos com `git ls-files --eol` (os
tracked) e `file` (os novos, que o `ls-files` não lista): `pipeline_item_finder.rb`,
`pipeline_items_controller.rb`, `pipelines_controller.rb`, `macros_controller.rb`,
`macros_pipeline_execution_job.rb`, `pipeline_item.rb`, `pipeline_stage.rb`,
`action_cable_listener.rb` (+ spec), `export_item_service.rb`, `pipeline_item_actions.rb` e as duas
migrations: todos em LF.

**Causa da recorrência (investigada):**
- `.gitattributes` está ativo (`git check-attr text eol`: `text: set`, `eol: lf`) e o índice está em
  LF. Mas a regra só vale para o que o git **escreve** no working tree (checkout/reset). Ela não
  reescreve um arquivo que já foi extraído em CRLF - e este checkout tem 2045 dos 2156 `.rb`
  rastreados em CRLF (efeito do `core.autocrlf=true` de antes da regra existir).
- O Edit/Write em arquivo já existente preserva o line ending que o arquivo tem. Então todo `.rb`
  que uma sessão edita sem converter **continua CRLF**; é assim que `macros_controller.rb`,
  `action_cable_listener.rb` e os outros reincidiram: nenhuma ferramenta "voltou" o arquivo, ele
  nunca deixou de ser CRLF.
- O mtime deste arquivo é 2026-09-15 22:44, antes da auditoria de 2026-09-16 que o descreveu como
  LF, e ele não foi escrito desde então. Não consegui reproduzir aquele "estava em LF" - o mais
  provável é que a checagem daquele dia tenha lido o conteúdo pelo git (normalizado), não o arquivo
  em disco. Conclusão: não houve regressão, o arquivo nunca esteve em LF no disco.
- Armadilha de medição: `grep -c $'\r'` dentro de `$( )` no Git Bash desta máquina casa a letra
  "r", não CR, e dá contagem alta (total de linhas) mesmo com o arquivo em LF - foi o que fez
  esta task parecer, por alguns minutos, ter a árvore inteira em CRLF. Fora de `$( )` o `grep -c`
  funciona; o mais seguro é `git ls-files --eol <arquivo>` ou `file`.

**Não feito (fora de escopo):** normalizar a árvore inteira (`git add --renormalize .` ou um
re-checkout) resolveria a causa de fato, mas mexe em ~2000 arquivos do working tree e deve ser uma
decisão sua, feita com a árvore limpa. Enquanto isso, a regra prática é rodar `git ls-files --eol`
nos `.rb` que a sessão editou antes de fechar.
