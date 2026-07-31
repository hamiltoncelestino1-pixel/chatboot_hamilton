# Task: Teste end-to-end de que `AssignmentPolicy` tem precedência sobre a config direta

## Objetivo

A task `03` introduziu `assignment_mode_balanced?`, com precedência explícita: feature
flag `advanced_assignment` habilitada → `AssignmentPolicy` vinculada (se houver) →
`auto_assignment_config['assignment_mode']` da inbox. O caminho "sem policy" tem teste
de método privado **e** teste end-to-end (atribuição real ao agente menos ocupado). O
caminho "com policy vinculada" — que a própria task `03` chama de "regressão zero"
obrigatória — só tem cobertura no nível de método privado.

---

## Contexto importante

`spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb:71-78`:
```ruby
context 'with a linked AssignmentPolicy' do
  it 'still takes precedence over the inbox direct config' do
    assignment_policy.update!(assignment_order: 'balanced')
    inbox.update!(auto_assignment_config: {})

    expect(assignment_service.send(:assignment_mode_balanced?)).to be true
  end
end
```

Comparar com o teste irmão do caminho "sem policy" (linhas ~60-68 do mesmo arquivo), que
além do `send(:assignment_mode_balanced?)` também roda `perform_bulk_assignment` de
verdade e confirma que o agente com menos conversas abertas é quem recebe a próxima
atribuição.

Um regressão que quebrasse especificamente o branch `policy&.balanced?` de
`assignment_mode_balanced?` (por exemplo, se alguém reordenar a precedência ou
acidentalmente remover o `return true if policy&.balanced?` mantendo o resto
funcionando) passaria despercebida se só o teste de método privado existisse — porque
ele testa uma chamada isolada, não o fluxo real de atribuição.

`BalancedSelector` (`enterprise/app/services/enterprise/auto_assignment/balanced_selector.rb`)
já é usado pelo teste "sem policy" como referência de setup (2+ agentes com quantidades
diferentes de conversas abertas).

---

## O que precisa ser feito

Adicionar um teste end-to-end no bloco `context 'with a linked AssignmentPolicy'`,
espelhando o setup do teste "sem policy" já existente (2 agentes membros da inbox com
cargas diferentes de conversas abertas), mas com uma `AssignmentPolicy` `balanced`
vinculada à inbox e `auto_assignment_config` vazio/`round_robin` (para garantir que é a
policy, e não a config direta, decidindo o resultado). Rodar
`perform_bulk_assignment`/`perform_for_conversation` de verdade e confirmar que o agente
menos ocupado recebe a atribuição — igual ao teste irmão, só que pelo caminho da policy.

---

## Verificação

- Novo teste passa hoje (comportamento já correto — é só cobertura faltando).
- Reverter temporariamente o `return true if policy&.balanced?` de
  `assignment_mode_balanced?` (`enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`)
  e confirmar que o novo teste falha — isso confirma que ele de fato protege esse
  caminho, ao contrário do teste de método privado isolado.
- `bundle exec rubocop` limpo.
