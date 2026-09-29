# Task 17 — Fix: automação "criar task" sem título falha silenciosamente

Severidade: 🟢 Baixa. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/services/concerns/pipeline_item_actions.rb:46-57`:

```ruby
def create_task_for_pipeline_item(pipeline_item, attrs)
  assignee_id = attrs[:assignee_id].presence || pipeline_item.assignee_id
  log_missing_task_assignee(pipeline_item) if assignee_id.blank?

  pipeline_item.account.tasks.create!(
    title: attrs[:title],
    # ...
  )
end
```

Sem fallback nem validação prévia de `attrs[:title]`. No frontend,
`app/javascript/dashboard/components/widgets/AutomationActionCreatePipelineItemTaskInput.vue:13-18`
não marca o campo título como obrigatório no formulário.

**Efeito**: admin cria uma automação "criar task" sem preencher o título; `Task.create!` falha
por `validates :title, presence: true` (`app/models/task.rb:51`) e a exceção é engolida pelo
`rescue StandardError` genérico do `AutomationRules::PipelineActionService`/
`Macros::PipelineExecutionService` (mesmo padrão de todo o resto desses arquivos — não é uma
inconsistência nova). Efeito prático: a automação "roda" sem erro visível, mas nunca cria
nenhuma task.

## O que corrigir

Marcar o campo "title" como obrigatório em
`AutomationActionCreatePipelineItemTaskInput.vue` (validação de formulário no client, mesmo
nível de obrigatoriedade que outros campos required de ações de automação no projeto),
impedindo salvar a automação sem título preenchido. Não é necessário mudar o rescue genérico
do backend (mantém o padrão já estabelecido no arquivo) — o fix é evitar que a configuração
inválida seja salva, não tratar o erro em runtime.

## Testes

Testar manualmente: tentar salvar uma automação com a ação "criar task" sem preencher o
título — deve bloquear o salvamento com indicação de campo obrigatório, mesmo padrão visual
dos outros campos required do formulário de automação.

## Critério de pronto

- Não é possível salvar uma automação com ação "criar task" sem título preenchido.
- `pnpm eslint:fix` limpo no arquivo tocado.
