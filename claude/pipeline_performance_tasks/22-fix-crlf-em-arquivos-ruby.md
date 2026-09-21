# Task 22 — Fix: dois arquivos Ruby foram salvos com CRLF

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

Dois arquivos tocados pela task 07 foram gravados com terminadores CRLF, enquanto no `HEAD`
estavam em LF:

| Arquivo | HEAD | Working tree |
|---|---|---|
| `app/controllers/api/v1/accounts/macros_controller.rb` | LF | **CRLF** |
| `app/jobs/macros_pipeline_execution_job.rb` | LF | **CRLF** |

Rubocop reclama dos dois:

```
app/controllers/api/v1/accounts/macros_controller.rb:1:1: C: Layout/EndOfLine: Carriage return character detected.
app/jobs/macros_pipeline_execution_job.rb:1:1: C: Layout/EndOfLine: Carriage return character detected.
```

Nenhum outro arquivo Ruby tocado na leva tem o problema (`pipeline_item_finder.rb`,
`pipeline_items_controller.rb`, `pipelines_controller.rb`, `pipeline_stages_controller.rb` e
`pipeline_item.rb` estão em LF), então é um acidente pontual de edição no Windows, não uma
configuração do repositório.

Além do lint, tem um custo prático: o `git diff` desses dois arquivos marca **todas** as linhas
como alteradas, o que esconde a mudança real na revisão de PR.

## O que corrigir

1. Reconverter os dois arquivos para LF.
2. Rodar `bundle exec rubocop` nos dois e confirmar que `Layout/EndOfLine` sumiu.
3. Conferir com `git diff --stat` que o diff dos dois voltou a mostrar só as linhas realmente
   alteradas pela task 07.
4. Enquanto estiver nisso, verificar se o repositório tem `.gitattributes` com `* text=auto` (ou
   equivalente) e, se não tiver, avaliar acrescentar — é o que evita o problema se repetir em
   qualquer edição futura neste ambiente Windows/Docker. Se for acrescentar, fazer num commit
   separado: `.gitattributes` pode renormalizar a árvore inteira e não deve entrar junto com um
   fix de duas linhas.

## Testes

- `bundle exec rubocop --force-exclusion app/controllers/api/v1/accounts/macros_controller.rb app/jobs/macros_pipeline_execution_job.rb` sem ofensas.
- `git diff` dos dois arquivos mostra apenas as linhas da task 07.
- `bundle exec rspec spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` continua
  passando (sanidade — conversão de line ending não deve mudar comportamento).

## Critério de pronto

- Os dois arquivos em LF, sem ofensa de `Layout/EndOfLine`.
- Diff limpo e legível.
- Decisão sobre `.gitattributes` registrada aqui (feito em commit separado, ou descartado com o
  motivo).

## Resultado (2026-09-18)

`macros_pipeline_execution_job.rb` já tinha sido corrigido de passagem na task 19 (precisei
tocar o arquivo mesmo, então converti ali). Faltava só `macros_controller.rb` — convertido para
LF agora.

`bundle exec rubocop --force-exclusion` nos dois: **0 ofensas**. `git diff` de ambos mostra só as
linhas reais da task 07 (confirmado lendo o diff completo, não só o stat). `bundle exec rspec`
(pipeline_items_controller): 6/6 passando.

**`.gitattributes`: acrescentado `*.rb text eol=lf`**, no mesmo estilo das entradas já existentes
(`*.sh`, `docker/entrypoints/**`, `bin/*` — todas específicas por padrão, não um `* text=auto`
genérico que renormalizaria a árvore inteira). Motivo registrado no comentário do próprio
arquivo: já aconteceu duas vezes neste ambiente Windows/Docker sem nenhuma config de editor
identificável como causa. **Não é o fix de duas linhas** — é uma linha adicional no
`.gitattributes`, mas ainda uma mudança logicamente separada do fix de CRLF em si (ela só previne
recorrência futura, não corrige nada retroativamente); registrando aqui para quem for revisar/
commitar decidir se quer separar em dois commits.
