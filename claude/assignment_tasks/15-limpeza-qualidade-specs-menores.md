# Task: Limpeza de qualidade menor nos specs + decisão documentada sobre `spec/db/migrate/`

## Objetivo

Quatro ajustes pequenos de qualidade/consistência nos specs adicionados pelas tasks
`01`-`07`. Nenhum é bug funcional — são nomenclatura confusa, um `it` cobrindo dois
cenários, um padrão de setup inconsistente com o resto do arquivo, e uma decisão de
convenção de diretório que foi tomada sem registrar a justificativa pedida pelo próprio
spec da task `01`.

---

## 1. Nome de teste não bate com o que é testado

`spec/services/auto_assignment/assignment_service_spec.rb:348-356`:
```ruby
it 'skips assignment when no team members are available' do
  inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => true })
  allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  conversation_with_team = create(:conversation, inbox: inbox, team: team, assignee: nil)
  ...
```
O `team` usado aqui tem membro (`team_member`, criado no `before` do describe) — o
cenário real é "nenhum membro do time está **online**, com `restrict_to_online_agents`
forçado", não "nenhum membro disponível". O cenário de time genuinamente vazio já é
coberto à parte em
`spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb`
(teste de fronteira de time, sem fallback). Comportamento correto, nome confuso.

**Ajuste**: renomear para algo como `'skips assignment when restrict_to_online_agents
is true and no team member is online'`.

## 2. Dois cenários dentro de um `it`, instância de serviço inconsistente

`spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb:45-51`:
```ruby
it 'uses round robin when assignment_mode is round_robin or absent' do
  inbox.update!(auto_assignment_config: {})
  expect(assignment_service.send(:assignment_mode_balanced?)).to be false

  inbox.update!(auto_assignment_config: { 'assignment_mode' => 'round_robin' })
  expect(AutoAssignment::AssignmentService.new(inbox: inbox).send(:assignment_mode_balanced?)).to be false
end
```
Dois cenários independentes ("ausente" e `"round_robin"` explícito) num único `it` — uma
falha não diz qual dos dois quebrou. A segunda asserção também instancia um serviço novo
em vez de reaproveitar o `let(:assignment_service)` usado no resto do arquivo (sem
efeito prático hoje, mas inconsistente).

**Ajuste**: separar em dois `it`s, ambos usando `assignment_service`.

## 3. Inconsistência de setup: mutar `let!` vs `build(...)`

`spec/enterprise/models/inbox_spec.rb:60-81` (novos testes de
`#ensure_valid_assignment_mode`):
```ruby
it 'accepts round_robin' do
  inbox.auto_assignment_config = { 'assignment_mode' => 'round_robin' }
  expect(inbox).to be_valid
end
```
mutam o `inbox` (`let!(:inbox) { create(:inbox) }`) compartilhado do topo do arquivo. O
teste vizinho de `#ensure_valid_max_assignment_limit` (linhas ~22-27) usa
`build(:inbox, account: account, auto_assignment_config: {...})` — registro novo, não
persistido, por caso. Funciona do jeito atual (cada `it` recria o `let!`), mas foge do
padrão já estabelecido no mesmo arquivo, no bloco imediatamente acima.

**Ajuste**: alinhar ao padrão `build(:inbox, ...)` do teste irmão.

## 4. `spec/db/migrate/` sem precedente documentado no projeto

Arquivo: `spec/db/migrate/20260729120000_enable_advanced_assignment_globally_spec.rb`.

O texto da própria task `01` pedia para verificar se já existe spec para as duas
migrations citadas como precedente (`db/migrate/20260409091202_...` e
`db/migrate/20260120121402_...`) antes de criar um padrão novo de teste para
migrations. Confirmado: **nenhuma das duas tem spec**, e não existe `spec/db/` nem
`spec/migrations/` em nenhum outro ponto do histórico do repo — todo outro diretório de
spec espelha uma raiz autoloadada (`spec/models` ↔ `app/models`, `spec/services` ↔
`app/services`, `spec/lib` ↔ `lib`). Esse é o único caminho de spec do projeto que
espelha `db/` em vez de uma raiz de autoload, e precisa de
`require Rails.root.join('db/migrate/...')` manual porque `db/migrate` não está no
autoload/eager-load path do Rails — funciona hoje, mas cria risco de colisão de nome de
classe (`TypeError: superclass mismatch`) se uma spec de migration futura carregar outra
classe de migration com nome igual na mesma run de testes.

**Ajuste**: não é um bug — é uma decisão de convenção de teste tomada sem documentar a
justificativa que o próprio spec da task `01` pedia para registrar. Decidir e documentar
explicitamente (comentário no topo do arquivo de spec, ou nota na visão geral) por que
esse padrão novo foi criado em vez de seguir os dois precedentes (que não têm spec
automatizado, só verificação manual via `bin/rails console`) — ou, alternativamente,
avaliar mover/isolar esse spec de um jeito que reduza o risco de colisão de classe
citado acima (por exemplo, um helper que isola o `require` e evita recarregar a mesma
constante entre exemplos).

---

## Verificação

- Os 3 ajustes de teste (itens 1-3) não mudam nenhum resultado de teste, só
  nome/estrutura/consistência — a suite inteira continua verde.
- Item 4: uma frase de justificativa (ou a mudança estrutural escolhida) está registrada
  de forma visível para quem ler o spec depois.
- `bundle exec rubocop` limpo nos arquivos alterados.
