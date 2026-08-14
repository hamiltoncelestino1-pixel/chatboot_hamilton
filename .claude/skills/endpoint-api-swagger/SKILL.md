---
name: endpoint-api-swagger
description: Use ao criar ou modificar um endpoint de API neste projeto Rails (Api::V1::Accounts::*, resposta em Jbuilder, documentação Swagger validada por Skooma). Ativar quando o pedido envolver "criar endpoint novo", "adicionar rota de API", "novo controller de accounts", "action nova em um controller existente", ou tocar em app/controllers/api/, app/views/api/**/*.json.jbuilder, config/routes.rb ou swagger/.
---

# Endpoint de API neste projeto (Api::V1::Accounts + Jbuilder + Swagger/Skooma)

Exemplo completo e real (controller, views, rotas, YAMLs de Swagger, rake task, spec):
[references/exemplo-pipeline-items.md](references/exemplo-pipeline-items.md)

## Passo a passo

1. **Controller**: herdar de `Api::V1::Accounts::BaseController`
   (`app/controllers/api/v1/accounts/base_controller.rb` — já traz `before_action
   :current_account` e `around_action :switch_locale_using_account_locale`), que herda de
   `Api::BaseController` (autenticação dupla: token de agent-bot vs sessão Devise,
   `app/controllers/api/base_controller.rb:4-6`). Adicionar `before_action
   :check_authorization` — chama `authorize(model)` do Pundit inferindo a policy a partir de
   `controller_name.classify.constantize` (`api/base_controller.rb:14-18`), então não precisa
   passar o model explicitamente se o nome do controller bater com o da policy.

2. **Toda query que retorna registro(s) de conta passa por `policy_scope(...)`** antes de
   `.find`/filtro — inclusive em lookups aninhados dentro de uma action de recurso filho
   (ex. `policy_scope(Current.account.pipelines).find(...)` dentro de uma action de item que
   pertence a um pipeline). Strong params em métodos privados por action (`create_params`,
   `update_params`, etc. — um método por formato de payload, não um único genérico).

3. **Resposta em Jbuilder, sempre** — **não existe `ActiveModel::Serializer` nem pasta
   `app/serializers/` neste projeto**, confirmado. Views ficam em
   `app/views/api/v1/accounts/<recurso>/*.json.jbuilder`. Padrão real: `index`/`show`/
   `create`/`update` costumam ser wrappers curtos delegando pra uma partial compartilhada:
   ```ruby
   # show.json.jbuilder / create.json.jbuilder / update.json.jbuilder (idênticos)
   json.partial! 'api/v1/models/<recurso>', formats: [:json], resource: @item

   # index.json.jbuilder
   json.array! @items do |item|
     json.partial! 'api/v1/models/<recurso>', formats: [:json], resource: item
   end
   ```
   `destroy` normalmente não tem view (`head :ok`, sem `render`). Se uma action fora do CRUD
   padrão precisa devolver o mesmo formato de outra, chame `render :show` explicitamente em
   vez de duplicar a partial.

4. **Rota** em `config/routes.rb`, aninhada dentro do bloco de recursos de `accounts`. Use
   `collection { post :algo }` / `member { post :algo }` para actions extras fora do CRUD
   padrão (ver exemplo completo com `reorder`/`export` na referência).

5. **Documentar no Swagger** — são **4 arquivos, sempre registrados num índice**; nunca crie
   um YAML solto sem referenciá-lo:
   - **Operação**: `swagger/paths/application/<área>/<recurso>/<action>.yml` — `tags`,
     `operationId`, `security: [{ userApiKey: [] }]`, `requestBody` (se aplicável),
     `responses` (200 com `$ref` pro schema, 401 com `$ref` pro erro padrão).
   - **Registrar a URL**: `swagger/paths/index.yml` — cada verbo HTTP da URL faz `$ref` pro
     arquivo de operação correspondente.
   - **Schema de resposta**: `swagger/definitions/resource/<model>.yml`, registrado como
     chave em `swagger/definitions/index.yml`.
   - **Parâmetro de path novo** (se houver): `swagger/parameters/<nome>.yml`, registrado em
     `swagger/parameters/index.yml`.

   **Se a `tag` usada for nova** (nenhum endpoint existente usa esse nome ainda), tem um
   **5º registro obrigatório** que não segue o padrão `$ref`/pasta acima: `swagger/index.yml`
   mantém, à parte de tudo isso, uma lista mestra `tags:` (nome + description) e um
   `x-tagGroups:` (quais tags aparecem em cada grupo do menu — Platform/Application/Client/
   Others) que o Swagger UI usa pra montar a navegação lateral. Uma tag nova só citada nos
   YAMLs de operação **funciona** (o Skooma valida a resposta normalmente, o
   `swagger:build` não erra) mas **não aparece no menu do Swagger UI** — o JSON gerado tem os
   paths certos, só não há como navegar até eles pela UI. Adicionar a tag em `swagger/index.yml`
   nos dois lugares (bloco `tags:` e dentro do grupo certo em `x-tagGroups:`, normalmente
   `Application` pra endpoints de conta) antes de considerar a documentação pronta.

6. **Rodar o build do Swagger** antes de considerar o endpoint pronto:
   ```bash
   bundle exec rails swagger:build
   # ou, no ambiente Docker deste projeto:
   docker exec chatwoot-noble-rails-1 bundle exec rails swagger:build
   ```
   Isso regenera `swagger/swagger.json` (`lib/tasks/swagger.rake`, resolve todo `$ref`
   recursivamente e escreve o JSON final via `JsonRefs.call` + `JSON.pretty_generate`).
   **`swagger/swagger.json` é artefato gerado — nunca editar à mão.**

7. **Por que isso é obrigatório, não decorativo**: `spec/rails_helper.rb:79-81` registra
   ```ruby
   path_to_openapi = Rails.root.join('swagger/swagger.json')
   config.include Skooma::RSpec[path_to_openapi], type: :request
   ```
   **Toda spec `type: :request`** (inferida automaticamente pelo local do arquivo/`describe`)
   tem sua resposta HTTP validada contra `swagger/swagger.json` — **sem nenhuma assertion
   explícita de schema no teste**. Se o YAML não bater com o formato real da resposta (campo
   faltando no schema, status não documentado, endpoint não registrado em
   `paths/index.yml`), a spec falha sozinha, mesmo que o teste em si só verifique um campo
   qualquer como `response.parsed_body['id']`.

8. **Lembrete de regra do `AGENTS.md`**: não escrever specs a menos que peçam
   explicitamente. Mas **se já existir** uma spec de request pro endpoint que você está
   mudando (repare: pode estar em `spec/controllers/...` mas ainda assim ser `type:
   :request` — é o `describe` que decide, não a pasta), ela vai quebrar sem o Swagger
   atualizado. Ou seja: ao alterar um endpoint com spec existente, atualizar o Swagger deixa
   de ser opcional mesmo sem pedido explícito de "escreva testes".
