# Task: Log Temporário — Diagnosticar 500 no Filtro de Conversas

## Objetivo

Em produção (`chat.advocaciamazza.com`), aplicar um filtro na lista de conversas está retornando
`POST /api/v1/accounts/1/conversations/filter?page=... 500 (Internal Server Error)` sem nenhum
detalhe no console do navegador (resposta genérica, esperado em produção com
`consider_all_requests_local = false`).

Esta task **não corrige nada ainda** — só adiciona um log temporário, sem nenhuma mudança de
comportamento, pra confirmar com certeza a causa antes de mexer em qualquer lógica de filtro. A
correção de verdade vira uma task separada depois que o log confirmar a hipótese.

---

## Diagnóstico (já investigado, alta confiança)

Rastreando o código real do endpoint (`Api::V1::Accounts::ConversationsController#filter` →
`Conversations::FilterService` → `FilterService#filter_operation` em
`app/services/filter_service.rb`), encontrei um ponto de alta suspeita:

**`app/services/filter_service.rb:29`**
```ruby
when 'equal_to', 'not_equal_to'
  attribute_data_type = standard_attribute_data_type(query_hash['attribute_key'])
  if attribute_data_type == 'date'
    @filter_values["value_#{current_index}"] = Date.iso8601(query_hash['values'][0].to_s)
    # ...
```

`Date.iso8601(...)` é chamado **sem nenhum rescue**, dentro do branch dos operadores
`equal_to`/`not_equal_to` pra atributos do tipo `date` (`created_at`/`last_activity_at`) —
funcionalidade adicionada recentemente neste fork (ver `claude/tasks/03-feat-filter-date-equal-to-operator.md`).
Se o valor vier vazio, `null`, ou num formato que não seja ISO-8601, essa linha estoura
`ArgumentError`/`Date::Error`.

Esse erro **não é capturado** em nenhum lugar do caminho:
- `app/controllers/api/v1/accounts/conversations_controller.rb:50-59` só trata as 4 exceções de
  `CustomExceptions::CustomFilter` (`InvalidAttribute`/`InvalidOperator`/`InvalidQueryOperator`/
  `InvalidValue`).
- `app/controllers/concerns/request_exception_handler.rb` (handler global) só trata
  `ActiveRecord::RecordNotFound`/`Pundit::NotAuthorizedError`/`ActionController::ParameterMissing`.

O erro sobe cru até o handler padrão do Rails, que devolve o 500 opaco — exatamente o sintoma
reportado.

**Sobre os logs já existentes**: confirmado que `RAILS_LOG_TO_STDOUT` é `true` por padrão
(`config/environments/production.rb`), então o backtrace bruto desse erro provavelmente já está no
STDOUT do container, acessível via `docker compose -f docker-compose.production.yaml logs -f rails`.
O log temporário desta task complementa isso: adiciona o **payload exato do filtro** que o agente
estava aplicando (o backtrace sozinho não mostra isso), essencial pra reproduzir localmente e saber
qual view/filtro salvo está causando o problema.

---

## Mudança única — `app/controllers/api/v1/accounts/conversations_controller.rb`

### Estado atual (linhas 50-59)

```ruby
def filter
  result = ::Conversations::FilterService.new(params.permit!, current_user, current_account).perform
  @conversations = result[:conversations]
  @conversations_count = result[:count]
rescue CustomExceptions::CustomFilter::InvalidAttribute,
       CustomExceptions::CustomFilter::InvalidOperator,
       CustomExceptions::CustomFilter::InvalidQueryOperator,
       CustomExceptions::CustomFilter::InvalidValue => e
  render_could_not_create_error(e.message)
end
```

### Mudança proposta

Adicionar um segundo `rescue`, **depois** do já existente (Ruby avalia em ordem — as 4 exceções
específicas continuam tratadas exatamente como hoje, sem nenhuma mudança nesse caminho). O novo
`rescue StandardError` captura qualquer coisa não prevista (incluindo o `ArgumentError` suspeito),
loga o necessário pra diagnosticar, e **relança a exceção com `raise`** — a resposta HTTP continua
sendo exatamente o mesmo 500 de hoje, sem nenhuma mudança de comportamento pro usuário. É puramente
um "grampo" de observação.

```ruby
def filter
  result = ::Conversations::FilterService.new(params.permit!, current_user, current_account).perform
  @conversations = result[:conversations]
  @conversations_count = result[:count]
rescue CustomExceptions::CustomFilter::InvalidAttribute,
       CustomExceptions::CustomFilter::InvalidOperator,
       CustomExceptions::CustomFilter::InvalidQueryOperator,
       CustomExceptions::CustomFilter::InvalidValue => e
  render_could_not_create_error(e.message)
rescue StandardError => e
  # TEMP DEBUG (remover após diagnosticar o 500 do filtro de conversas — chat.advocaciamazza.com)
  Rails.logger.error(
    "[FILTER_DEBUG_TEMP] account=#{current_account&.id} user=#{current_user&.id} " \
    "error=#{e.class}: #{e.message} payload=#{params.permit!.to_h.except(:controller, :action, :account_id)}"
  )
  Rails.logger.error("[FILTER_DEBUG_TEMP] backtrace:\n#{e.backtrace&.first(15)&.join("\n")}")
  raise
end
```

**Por que essa abordagem:**
- Tag `[FILTER_DEBUG_TEMP]` única e fácil de `grep` — e fácil de encontrar/remover depois via
  `grep -rn "FILTER_DEBUG_TEMP"`. O comentário no código já deixa explícito que é temporário.
- `raise` sem argumento dentro do `rescue` relança a exceção original (mesma classe, mensagem,
  backtrace) — o Rails trata exatamente do jeito que trata hoje. Nada muda pra quem usa o sistema.
- `params.permit!.to_h` (excluindo `controller`/`action`/`account_id`, ruído de roteamento) dá o
  payload exato do filtro montado na tela — confirma se é mesmo um filtro de data com
  `equal_to`/`not_equal_to` e valor inválido, ou outra causa.
- Não precisa de gem nova nem de Sentry configurado (confirmado: `SENTRY_DSN` não está setado nesse
  ambiente pelo que dá pra ver no repo) — só `Rails.logger`, que já vai pro STDOUT do container.

---

## Como aplicar e observar

1. Deploy da imagem com essa mudança, seguindo `claude/09-deploy-producao.md` (build/push da
   imagem; no servidor: `docker compose -f docker-compose.production.yaml pull && docker compose -f docker-compose.production.yaml up -d`).
2. Reproduzir o filtro que estava quebrando (pedir pro agente repetir a ação, ou reproduzir você
   mesmo).
3. No servidor: `docker compose -f docker-compose.production.yaml logs -f rails | grep FILTER_DEBUG_TEMP`.
4. A linha `payload=...` + a linha de backtrace confirmam (ou descartam) a suspeita da linha 29 de
   `filter_service.rb`.

---

## Depois de confirmado

Assim que o log real confirmar a causa, criar uma task de correção separada: envolver o
`Date.iso8601` num rescue que levanta `CustomExceptions::CustomFilter::InvalidValue` (mesmo padrão
já usado pelos outros filtros em `filter_service.rb`), transformando o 500 num 422 com mensagem
clara — e remover este bloco de log temporário na mesma mudança, já que terá cumprido o papel.

---

## Verificação

1. Localmente: montar um filtro de conversa com atributo `created_at`/`last_activity_at`, operador
   "Igual a", valor vazio — confirmar que aparece `[FILTER_DEBUG_TEMP]` no log local com payload e
   backtrace, e que a resposta HTTP continua 500 (comportamento inalterado, só o log é novo).
2. Confirmar que um filtro **válido** continua funcionando normalmente — o novo
   `rescue StandardError` não deve interferir no caminho de sucesso nem no das 4 exceções já
   tratadas.
3. Deploy em produção, reproduzir o filtro problemático, confirmar que `[FILTER_DEBUG_TEMP]`
   aparece no log do container com o payload real do agente.
