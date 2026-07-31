# Task: Corrigir teste inválido "returns 0 when no agents are online"

## Objetivo

`spec/services/auto_assignment/assignment_service_spec.rb` tem um teste pré-existente
que não foi atualizado depois da task `05` (fim do "só agente online" por default). Ele
ainda passa, mas não pelo motivo que descreve — não está testando o que o nome diz.

---

## Contexto importante

`spec/services/auto_assignment/assignment_service_spec.rb:50-57`:
```ruby
it 'returns 0 when no agents are online' do
  allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

  assigned_count = service.perform_bulk_assignment(limit: 1)

  expect(assigned_count).to eq(0)
  expect(conversation.reload.assignee).to be_nil
end
```

Dois problemas simultâneos:

1. `inbox` (o `let` do topo do arquivo) não tem
   `auto_assignment_config: { 'restrict_to_online_agents' => true }`. Depois da task
   `05`, isso significa que `restrict_to_online_agents?` é `false` por default —
   `available_agents` (`app/models/concerns/inbox_agent_availability.rb`) não filtra
   mais por online. Mockar `get_available_users` para `{}` não tem mais nenhum efeito
   sobre elegibilidade.
2. `conversation` (também um `let` do topo) nunca é referenciado antes de
   `perform_bulk_assignment` rodar — como `let` é lazy, a conversa **não existe no
   banco** ainda quando a atribuição em massa executa. Comparar com testes vizinhos no
   mesmo arquivo, que fazem algo como `conversation # garante que existe` antes de
   chamar o método sob teste, justamente para evitar esse problema.

Ou seja: o teste passa hoje — mas passa porque não há nenhuma conversa pendente para
atribuir, não porque os agentes estão offline. Ele continuaria passando mesmo que
`available_agents` regredisse silenciosamente para o filtro antigo (só online), porque
nunca havia uma conversa real no cenário para expor a regressão.

Padrão já usado corretamente mais abaixo no mesmo arquivo (por volta da linha 349, teste
adicionado pela task `06`), que força a restrição explicitamente antes de testar o
cenário "só online":
```ruby
inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => true })
```

---

## O que precisa ser feito

Reescrever este teste para refletir o comportamento real que deve ser verificado. Duas
opções, escolher a que fizer mais sentido dado o que já está coberto em
`spec/models/concerns/inbox_agent_availability_spec.rb` (criado pela task `05`) e em
`spec/services/auto_assignment/agent_assignment_service_spec.rb` (task `06`):

- **Corrigir**: seguir o padrão da linha ~349 — setar
  `restrict_to_online_agents: true` explicitamente, garantir que a `conversation`
  exista antes da chamada (`conversation` sozinho numa linha, ou `create(...)`
  explícito), e então confirmar que sem ninguém online (`get_available_users` mockado
  para `{}`) a atribuição não acontece.
- **Remover**: se o cenário "restrict_to_online_agents=true e ninguém online → sem
  atribuição" já estiver coberto de forma equivalente ou melhor em algum dos specs
  citados acima, remover este teste redundante em vez de duplicá-lo aqui.

---

## Verificação

- O teste corrigido (ou sua remoção + justificativa) não deve alterar o resultado de
  nenhum outro teste do arquivo.
- Rodar o arquivo isolado (`bundle exec rspec spec/services/auto_assignment/assignment_service_spec.rb`)
  e confirmar que o teste falha se `restrict_to_online_agents?`/`available_agents` for
  temporariamente revertido para o comportamento antigo (só online) — isso confirma que
  o teste agora de fato protege contra regressão, ao contrário do estado atual.
- `bundle exec rubocop` limpo.
