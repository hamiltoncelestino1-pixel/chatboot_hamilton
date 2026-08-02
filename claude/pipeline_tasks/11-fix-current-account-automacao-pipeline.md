# Task 11 — Fix: `Current.account` nunca setado no contexto assíncrono de automação de pipeline

Task de correção pós-implementação das tasks 01, 02, 04 e 09. Achado na auditoria de
2026-08-01 (ver `claude/pipeline_tasks/00-visao-geral.md` para o épico original). **Prioridade
mais alta desta rodada de correção** — é o único achado com potencial de travar um
`db:migrate` em produção.

## Objetivo

`PipelineItem#assignee_must_be_pipeline_member` (`app/models/pipeline_item.rb:153-159`) permite
um assignee que seja **administrador da conta**, mesmo sem ser membro explícito do pipeline:

```ruby
def assignee_must_be_pipeline_member
  return if assignee_id.blank?
  return if assignee.administrator?
  return if pipeline.members.exists?(id: assignee_id)

  errors.add(:assignee_id, I18n.t('errors.pipeline_item.assignee_not_member'))
end
```

`assignee.administrator?` (`app/models/concerns/user_attribute_helpers.rb:24-36`) só funciona se
`Current.account` estiver setado:

```ruby
def current_account_user
  account_users.find { |ac_usr| ac_usr.account_id == Current.account.id } if Current.account
end

def administrator?
  current_account_user&.administrator?
end
```

Isso é verdade em qualquer request HTTP normal (setado no controller), mas **nenhum** dos
serviços novos de automação de pipeline seta `Current.account`:

- `AutomationRules::ActionService#initialize` (`app/services/automation_rules/action_service.rb:4-9`)
  — só seta `Current.executed_by = rule`.
- `AutomationRules::PipelineActionService#initialize` (`app/services/automation_rules/pipeline_action_service.rb:10-15`)
  — mesma coisa.

**Cenário concreto de falha:** uma regra de automação com `assign_pipeline_item_agent` (ou
`create_pipeline_item` com `assignee_mode` explícito) resolvendo para um administrador da conta
que **não é membro explícito do pipeline** falha com `ActiveRecord::RecordInvalid`
("Assignee must be a member of the pipeline"), engolido silenciosamente pelo `rescue StandardError`
por-ação — a ação nunca funciona nesse caso, sem nenhum sinal visível de erro pro usuário que
configurou a automação. O mesmo cenário funciona normalmente num request HTTP direto
(`PipelineItemsController`), porque lá `Current.account` já está setado — a inconsistência só
aparece em automação/macro.

## Segundo ponto de falha (mais grave) — migration de mesclagem de duplicados

`lib/pipeline_items/duplicate_merger.rb` já tinha identificado esse mesmo problema e contornado
corretamente com um helper próprio, independente de `Current.account`:

```ruby
# Reimplemented rather than reusing PipelineItem#assignee_must_be_pipeline_member's
# User#administrator? check: that helper reads Current.account, which isn't set in a
# rake task/migration context and would silently treat every admin as non-admin here.
def assignee_valid_for_pipeline?(item, assignee_id)
  AccountUser.exists?(account_id: item.account_id, user_id: assignee_id, role: :administrator) ||
    item.pipeline.members.exists?(id: assignee_id)
end
```

Só que dentro de `merge!`, depois de `assignee_valid_for_pipeline?` aprovar a adoção do assignee
de um perdedor, o `winning_item.save!` final roda a validação **real** do model
(`assignee_must_be_pipeline_member`, dependente de `Current.account`) — que em contexto de
migration/rake é `nil`, e pode **rejeitar o mesmo admin que acabou de ser aprovado** pelo helper
correto. Consequência:

- Na rake task `pipeline_items:merge_duplicates` (`lib/tasks/pipeline_items_dedup.rake`), isso
  cai no `rescue StandardError` por-grupo — o grupo fica "ERRORED", mas não quebra o processo
  inteiro.
- **Na migration automática `db/migrate/..._merge_duplicate_pipeline_items.rb` não há rescue
  nenhum** — se esse cenário específico ocorrer em dados reais de produção (contato duplicado
  onde um perdedor tem como assignee um admin não-membro do pipeline de destino), a migration
  **trava o `db:migrate` no meio do deploy** — exatamente o cenário que a task 02 pediu
  explicitamente para evitar deixando a migration de índice único por último.

## O que corrigir

1. Em `AutomationRules::ActionService#initialize` e `AutomationRules::PipelineActionService#initialize`,
   setar `Current.account = @account` (mirror do já existente `Current.executed_by = rule`) — ambos
   já têm `@account` disponível e já fazem `Current.reset` no `ensure` do `#perform`, então não há
   vazamento entre execuções.
2. Em `lib/pipeline_items/duplicate_merger.rb#merge!` (ou onde for mais apropriado no fluxo), setar
   `Current.account = winning_item.account` antes do `winning_item.save!` final, revertendo depois
   (ou reaproveitando o mesmo padrão de `ensure` já usado em outros serviços do épico). Isso garante
   que a validação real do model concorde com o que `assignee_valid_for_pipeline?` já aprovou,
   eliminando a divergência entre os dois critérios.
3. Não é necessário adicionar rescue na migration automática — a correção acima resolve a causa,
   não só o sintoma.

## Testes

- `spec/services/automation_rules/action_service_spec.rb` e
  `spec/services/automation_rules/pipeline_action_service_spec.rb` — novo exemplo: assignee
  resolvido é um administrador da conta **sem** ser `PipelineMember` explícito do pipeline →
  ação aplica normalmente (sem `RecordInvalid`).
- `spec/lib/pipeline_items/duplicate_merger_spec.rb` — novo exemplo: perdedor tem como assignee um
  administrador não-membro do pipeline de destino → grupo mescla com sucesso, admin é adotado no
  vencedor, sem erro na `save!` final.
- QA/verificação manual: rodar `pipeline_items:report_duplicates` e depois
  `pipeline_items:merge_duplicates` numa base local com esse cenário específico propositalmente
  criado (card duplicado, perdedor com assignee administrador não-membro).

## Critério de pronto

- Os 3 novos exemplos de spec acima passando.
- `Current.account` setado e resetado corretamente nos dois serviços de automação, sem
  vazamento entre execuções (confirmar com teste que uma segunda regra/ação não herda o
  `Current.account` de uma execução anterior de forma indevida — na prática, o `ensure` já cobre
  isso, só validar com um teste explícito).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
