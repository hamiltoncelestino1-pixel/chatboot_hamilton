# 05 — Novas Funcionalidades (Full-stack)

Receita para adicionar uma feature que cruza backend e frontend. Siga a ordem das camadas.

## Backend

1. **Migração** — `db/migrate/` cria/altera tabelas. Rode a migração para atualizar
   `db/schema.rb` (gerado, não editar à mão).
2. **Model** — `app/models/`. Adicione associações, validações e regras de dados.
   Use `conversation.rb` / `contact.rb` / `inbox.rb` como referência de padrões.
3. **Service** — `app/services/<dominio>/`. Coloque aqui a lógica de negócio.
   Procure antes um service existente para estender em vez de duplicar.
4. **Controller + rota** — `app/controllers/api/v1/accounts/` e registre em
   `config/routes.rb`. Mantenha o controller fino (valida → autoriza → chama service).
5. **Autorização** — `app/policies/`. Defina quem pode acessar.
6. **Eventos/assíncrono** (se houver efeito colateral) — `app/dispatchers/` +
   `app/listeners/` + `app/jobs/`.

## Frontend (dashboard)

7. **API client** — `app/javascript/dashboard/api/`. Função que chama o novo endpoint.
8. **Store (Vuex)** — `app/javascript/dashboard/store/modules/`. Estado + actions/mutations.
9. **Componente** — `app/javascript/dashboard/components/` ou `components-next/`. A UI.
10. **Rota/página** — `app/javascript/dashboard/routes/dashboard/`. Onde a tela aparece.
11. **Textos** — `app/javascript/dashboard/i18n/`. Sem strings hardcoded.

## Testes

12. **`spec/`** — espelha a estrutura de `app/`. Cubra model, service e request specs.

## Fluxo resumido

```
db/migrate → model → service → controller (+ routes.rb) → policy
   → [dispatcher/listener/job se necessário]
api/ (front) → store/modules → componente → routes/dashboard → i18n
   → spec/
```

## Boas práticas observadas no projeto
- Lógica pesada vive em **services**, não em models/controllers.
- Reaproveite **finders/builders** existentes.
- Feature nova grande? Considere uma **feature flag** em `config/features.yml`
  para liberar gradualmente.
- Se a feature for premium, o lugar pode ser `enterprise/` (ver [07-enterprise.md](07-enterprise.md)).
