# Task 17 — Limpeza: itens menores encontrados na auditoria do épico de pipeline

Task de correção/limpeza pós-implementação (várias tasks). Achados de baixa severidade da
auditoria de 2026-08-01, agrupados numa única task por serem pequenos e independentes entre si.
Pode ser feita em qualquer ordem em relação às tasks 11-16.

## 1. `assign_pipeline_team` não valida que o time pertence à conta

**Arquivo:** `app/services/concerns/pipeline_item_actions.rb` (método `assign_pipeline_team`).

```ruby
def assign_pipeline_team(pipeline_item, team_id)
  pipeline_item.update!(team_id: team_id)
end
```

Ao contrário do padrão já usado em `app/services/action_service.rb#assign_team`, que checa
`team_belongs_to_account?(team_ids)` antes de atribuir, `assign_pipeline_team` não valida que o
`team_id` pertence à mesma conta do pipeline (só existe a FK de banco
`add_foreign_key :pipeline_items, :teams`, sem escopo de conta). Um automation rule mal
configurado (ou um bug na resolução de `team_mode`) poderia, em tese, atribuir a um card um
`team_id` de outra conta.

**Corrigir:** adicionar uma guarda equivalente a `team_belongs_to_account?` (reaproveitar/mover
esse helper de `ActionService` para um lugar compartilhado se fizer sentido, ou replicar a mesma
checagem) antes do `update!` em `assign_pipeline_team`. Adicionar teste em
`spec/services/concerns/pipeline_item_actions_spec.rb` cobrindo: time de outra conta é rejeitado
(no-op logado, mirror do padrão de `log_no_pipeline_item`), time da mesma conta é aceito
normalmente.

## 2. `delegate :pipeline` sombreia `belongs_to :pipeline` em `pipeline_item.rb`

**Arquivo:** `app/models/pipeline_item.rb` (linhas 49 e 67).

```ruby
belongs_to :pipeline, optional: true   # linha 49 — associação nova (task 01), só para uso interno
...
delegate :pipeline, to: :pipeline_stage   # linha 67 — sobrescreve silenciosamente o reader acima
```

O `delegate` definido depois sobrescreve o método de leitura gerado pelo `belongs_to`. Funciona
hoje (o `pipeline_id` próprio é resincronizado à parte via `set_pipeline_id_from_stage`, e o
`delegate` é o caminho público de leitura intencional, conforme a task 01 pedia para preservar) —
mas é confuso para quem for mexer nesse arquivo depois, especialmente porque é justamente o
campo usado no filtro do broadcast de tempo real (`item.pipeline_id`).

**Corrigir:** não é uma mudança de comportamento — só clareza. Adicionar um comentário curto
acima do `delegate` explicando por que ele intencionalmente convive com o `belongs_to` (ex.: "o
belongs_to existe só para permitir o índice único/query direta por pipeline_id; a leitura pública
de `#pipeline` continua sendo via stage, de propósito, para não mudar comportamento existente").
Não remover nenhum dos dois — só documentar a convivência para não parecer um descuido.

## 3. Fallback de `custom_attribute_present?` aponta para `'conversation_attribute'` mesmo em condições de pipeline

**Arquivo:** `app/services/automation_rules/condition_validation_service.rb` (linhas ~61-67).

```ruby
ATTRIBUTE_MODEL = 'conversation_attribute'.freeze
...
def custom_attribute_present?(attribute_key, attribute_model)
  attribute_model = attribute_model.presence || self.class::ATTRIBUTE_MODEL
  @account.custom_attribute_definitions.where(attribute_model: attribute_model).find_by(attribute_key: attribute_key).present?
end
```

Isso só é acionado quando um `attribute_key` de condição não está em nenhum bloco padrão — ou
seja, é tratado como atributo customizado. `PipelineConditionsFilterService` já define sua
própria constante `ATTRIBUTE_MODEL` correta (`'pipeline_item_attribute'`, verificar nome exato no
arquivo), mas o fallback do método acima usa `self.class::ATTRIBUTE_MODEL` — o que já deveria
funcionar corretamente por polimorfismo **se** `PipelineConditionsFilterService` sobrescrever essa
constante (confirmar isso ao implementar; se já estiver correto, esta subtask vira só um
comentário/teste de regressão, não uma correção de fato).

**Não é regressão da task 09** (custom attributes de `pipeline_item` não foram pedidos no escopo
original) — é um ponto cego a documentar para quando essa extensão for pedida no futuro.

**Corrigir:** confirmar (com um teste) que `PipelineConditionsFilterService::ATTRIBUTE_MODEL` de
fato sobrescreve o fallback corretamente quando/se uma condição de custom attribute de pipeline
for adicionada; se não sobrescrever, corrigir. Adicionar um comentário no código-fonte
explicando a limitação atual (nenhuma condição de custom attribute de pipeline existe ainda na
UI, então isso é só uma trava de segurança para o futuro).

## 4. `getActionOptions()`/`getMacroDropdownValues()` não têm branches para as ações de pipeline

**Arquivos:** `app/javascript/dashboard/helper/automationHelper.js#getActionOptions` e
`app/javascript/dashboard/composables/useMacros.js#getMacroDropdownValues`.

As tasks 05 (item 5) e 08 (item 3) pediam branches nessas duas funções para as novas ações de
pipeline. Isso não foi feito — os componentes novos ignoram a prop `dropdownValues` e buscam
pipelines/estágios/agentes/labels/times diretamente da store (`kanban/getPipelines`,
`agents/getVerifiedAgents`, etc.) dentro de si mesmos. Não causa bug (o valor não utilizado
simplesmente não é lido), mas diverge do que a spec pedia e pode confundir manutenção futura, que
pode esperar encontrar essas branches e não as achar.

**Corrigir:** não é obrigatório mudar o comportamento (a escolha de buscar direto da store dentro
dos componentes é razoável e evita prop drilling). Adicionar um comentário curto em
`getActionOptions()`/`getMacroDropdownValues()` (ex. próximo ao fim da função) documentando
explicitamente que as ações de pipeline são um caso à parte que resolve suas próprias opções
internamente, para que a próxima pessoa não gaste tempo procurando branches que não existem por
design.

## Critério de pronto

- Item 1: guarda de conta adicionada e testada em `assign_pipeline_team`.
- Item 2: comentário de clareza adicionado em `pipeline_item.rb`.
- Item 3: confirmado (com teste) o comportamento do fallback para condições de pipeline; corrigido
  se necessário; comentário documentando a limitação atual.
- Item 4: comentários adicionados nas duas funções documentando a decisão de design.
- `bundle exec rubocop -a` / `pnpm eslint:fix` limpos nos arquivos tocados.
