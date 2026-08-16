# Task 11 — Fix: `TaskDrop#contact_name` quebra padrão defensivo dos outros Drops

Severidade: 🟢 Baixa. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`app/drops/task_drop.rb:10-12`:

```ruby
def contact_name
  @obj.try(:contact).name.try(:capitalize) || 'Customer'
end
```

`.try(:contact)` protege só a primeira chamada (se `@obj` não responder a `:contact`, ou for
nil, retorna nil) — mas o `.name` seguinte é chamado direto no resultado, **sem** `.try`. Se
`@obj.contact` retornar `nil` por qualquer motivo, `nil.name` levanta `NoMethodError` antes
mesmo de chegar no `.try(:capitalize)` que viria depois.

Hoje é inofensivo na prática — `Task#contact_id` é `null: false` no schema, então uma
`Task` sempre tem um `contact` associado em dado consistente. Mas é uma inconsistência de
estilo/segurança de template Liquid: outros Drops do projeto (ex. `ContactDrop` e afins)
encadeiam `.try` de forma consistente em toda a cadeia, não só no primeiro elo.

## O que corrigir

```ruby
def contact_name
  @obj.try(:contact)&.name&.capitalize || 'Customer'
end
```

Alinha o estilo defensivo com o resto dos Drops do projeto — mudança de forma, não de
comportamento (dado consistente hoje continua retornando o mesmo valor).

## Critério de pronto

- `contact_name` usa encadeamento seguro (`&.`) em toda a cadeia, não só no primeiro
  elemento.
- Comportamento idêntico para dado consistente (nome do contato capitalizado).
- `bundle exec rubocop -a` limpo no arquivo tocado.
