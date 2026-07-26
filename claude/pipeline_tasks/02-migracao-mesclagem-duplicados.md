# Task 02 — Migração de dados: mesclar cards duplicados existentes

Parte do Grupo A ([visão geral](00-visao-geral.md)). Depende da task 01 (coluna `pipeline_id`
já backfilled). **Esta é a task de maior risco de todo o plano** — é destrutiva
(`destroy!` em registros) e encapsula uma decisão de negócio (critério de mesclagem). Não
apressar o merge desta task sem revisar o relatório de dry-run.

## Objetivo

Antes de travar a regra de card único com um índice único no banco (task 01 já criou a
coluna, mas o índice único e o NOT NULL só entram no fim desta task), é preciso resolver os
duplicados que já existem hoje: mesmo contato com mais de um card no mesmo pipeline,
espalhados em estágios diferentes.

## Critério de mesclagem (já confirmado com o cliente — não é escopo desta task decidir,
## só implementar)

Para cada grupo de cards duplicados (`pipeline_id` + `contact_id` repetidos):

1. **Vencedor por `stage_type`**: `won` > `normal` (dentro de `normal`, o de posição mais
   avançada) > `start` > `lost`. Um card em "Ganho" sempre vence; entre dois "normais", o
   mais avançado no funil vence.
2. **Empate dentro do mesmo `stage_type`**: `updated_at` mais recente vence.
3. **Empate residual**: maior `id` vence (critério determinístico final).
4. **`notes`**: concatenar as notas de todos os perdedores nas notas do vencedor, com
   marcador claro — nunca descartar silenciosamente:
   ```
   \n\n---\n[Mesclado do card #<id>, atualizado em <updated_at>]\n<notes do perdedor>
   ```
5. **`value`**: mantém o valor do vencedor — **não soma**. Para não perder o dado do
   perdedor mesmo sem somar, registrar o valor de cada perdedor no texto de nota mesclada
   (ex.: `[Card #<id> tinha valor: <value>]`).
6. **`conversation_id`**: se o vencedor não tiver e algum perdedor tiver, adotar (só se
   `conversation_must_belong_to_contact` continuar válido).
7. **`assignee_id`/`team_id`**: mantém do vencedor; se vencedor não tiver e um perdedor
   tiver, adotar — mas só se `assignee_must_be_pipeline_member` continuar válido para o
   vencedor após a troca; se não, ignorar e logar aviso (não travar a mesclagem do grupo por
   causa disso).
8. **`custom_attributes`**: merge raso — perdedor preenche só chaves ausentes no vencedor.
9. **Labels de pipeline**: união das labels do vencedor + todos os perdedores.
10. **`title`**: mantém o do vencedor, sem combinar.
11. Destruir todos os perdedores (`loser.destroy!`).

## 1. Extrair o algoritmo numa classe reutilizável

Novo arquivo `lib/pipeline_items/duplicate_merger.rb` — classe plain-Ruby com a lógica acima,
usada tanto pela rake task (passo 2) quanto pela migration (passo 3), **sem duplicar a
lógica em dois lugares**. Interface sugerida:

```ruby
module PipelineItems
  class DuplicateMerger
    def self.duplicate_groups(account_id: nil)
      # agrupa pipeline_items por (pipeline_id, contact_id) com count > 1
    end

    def self.merge_group!(pipeline_item_ids)
      # aplica o critério acima a um grupo específico, dentro de uma transação
    end
  end
end
```

## 2. Rake task de dry-run (rodar ANTES da migration em qualquer ambiente com dados reais)

Novo arquivo `lib/tasks/pipeline_items_dedup.rake`, task `pipeline_items:report_duplicates`:

- Para cada grupo de duplicados, loga (sem escrever nada no banco): nome do contato, nome do
  pipeline, e por card duplicado — estágio, `stage_type`, posição, valor, tamanho das notas,
  `conversation_id`, `updated_at`, e qual seria o vencedor previsto pelo critério acima.
- Deve ser possível rodar contra uma cópia de produção/staging e revisar a saída com um
  humano antes de aplicar a migration de verdade — este é o "relatório antes" que o cliente
  pediu explicitamente.

## 3. Rake task de execução (para rodar manualmente se necessário, fora do ciclo de deploy)

Segunda task no mesmo arquivo, `pipeline_items:merge_duplicates` — chama
`PipelineItems::DuplicateMerger.merge_group!` por grupo, dentro de
`ActiveRecord::Base.transaction` **por grupo** (não uma transação única pra tabela toda — uma
falha num grupo não deve reverter os grupos já mesclados com sucesso). Loga cada decisão
(`Rails.logger.info`): id vencedor, ids destruídos, o que foi concatenado — serve como trilha
de auditoria sem precisar de uma tabela nova (mantendo o MVP simples, conforme AGENTS.md).
Idempotente: depois que não há mais duplicados, rodar de novo é no-op.

## 4. Migration que aplica a mesclagem automaticamente no deploy

Novo arquivo `db/migrate/<timestamp>_merge_duplicate_pipeline_items.rb` — chama a mesma
`PipelineItems::DuplicateMerger` (não reimplementar a lógica), para garantir que a mesclagem
rode de forma consistente em todo `db:migrate` (dev, staging, produção).

## 5. Migration final: NOT NULL + índice único

Só depois que a mesclagem acima já rodou (na ordem de migrations, depois da task 4): novo
arquivo `db/migrate/<timestamp>_add_not_null_and_unique_index_to_pipeline_items_pipeline_id.rb`:

```ruby
change_column_null :pipeline_items, :pipeline_id, false
add_index :pipeline_items, [:pipeline_id, :contact_id], unique: true,
          name: 'index_pipeline_items_on_pipeline_id_and_contact_id'
```

Deixar por último de propósito: se houver um bug na lógica de mesclagem, ele aparece como
falha ao rodar esta migration (violação de unicidade), não como um `db:migrate` corrompido
no meio do deploy.

## Testes

- `spec/lib/pipeline_items/duplicate_merger_spec.rb` — fixtures com 2-3 duplicados em
  `stage_type`s diferentes; validar: vencedor correto em cada critério (stage_type, empate por
  updated_at, empate residual por id), concatenação de notas, união de labels, adoção de
  `conversation_id`/`assignee_id` só quando válido, destruição dos perdedores, idempotência
  (rodar duas vezes não gera erro nem muda nada na segunda vez).

## Antes de rodar em produção (checklist obrigatório, não pular)

1. Rodar `pipeline_items:report_duplicates` contra uma cópia/dump realista dos dados de
   produção.
2. Revisar a saída com o time/cliente — confirmar que os vencedores previstos fazem sentido
   de negócio.
3. Só então aplicar a migration em produção.

## Critério de pronto

- `PipelineItems::DuplicateMerger` com spec cobrindo o critério de mesclagem completo.
- Rake tasks de dry-run e execução funcionando localmente com dados de seed com duplicados
  propositais.
- As 2 migrations (mesclagem + NOT NULL/índice único) rodam limpo em sequência numa base
  local que tinha duplicados antes.
- Relatório de dry-run revisado antes de considerar esta task pronta para produção.
