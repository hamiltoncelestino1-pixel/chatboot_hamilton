# Task 10 — Limpeza: scope morto `Label.for_pipelines`

Severidade: 🟢 Baixa. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`app/models/label.rb:30`:

```ruby
scope :for_pipelines, -> { where(label_type: :pipeline_label) }
```

Esse scope nunca é chamado em nenhum lugar do código. `PipelineItem` usa o scope automático
gerado pelo enum de `label_type` (`account.labels.pipeline_label`,
`app/models/pipeline_item.rb:180`, em `labels_must_be_pipeline_type`) para o mesmo
propósito. `for_pipelines` é código morto/duplicado.

## O que corrigir

Remover o scope `for_pipelines` de `app/models/label.rb`. Antes de remover, confirmar via
busca (`grep -r "for_pipelines"` no repo, incluindo specs) que de fato não há nenhuma
referência — inclusive em código de frontend gerado dinamicamente ou testes que possam
depender dele.

## Critério de pronto

- Scope `for_pipelines` removido.
- Nenhuma referência quebrada em outros arquivos (confirmado por busca no repo antes da
  remoção).
- `bundle exec rubocop -a` limpo no arquivo tocado.
