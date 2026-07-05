# Task: Log temporário — Diagnosticar 500 no carregamento/filtro de conversas (agente específico)

## Objetivo

Em produção (`chat.advocaciamazza.com`), carregar mais conversas via scroll — tanto na aba "Minhas
conversas" quanto no filtro "Agente atribuído = Igual a" — retorna 500 quando as conversas
envolvidas são atribuídas à agente Anna Beatriz (`annabeatriz.chatwootmazza@gmail.com`). A primeira
página carrega normalmente; o erro só aparece ao rolar pra carregar mais (página 2+), travando o
carregamento indefinidamente. Nenhum outro agente reproduz o problema.

Esta task **não corrige nada ainda** — só adiciona logs temporários, sem nenhuma mudança de
comportamento, pra confirmar com certeza a causa antes de mexer em qualquer lógica. A correção de
verdade vira uma ou mais tasks separadas depois que os logs confirmarem a hipótese.

---

## Diagnóstico (já investigado, alta confiança)

Investigado via 3 agentes de exploração em paralelo (paginação/`ConversationFinder`,
`Conversations::FilterService`, e serialização/jbuilder) + leitura direta dos arquivos. Os três
convergiram na mesma causa raiz.

### Causa raiz

**`app/models/message.rb`**, método `conversation_push_event_data` (por volta da linha 163):

```ruby
def conversation_push_event_data
  {
    assignee_id: conversation.assignee_id,
    unread_count: conversation.unread_incoming_messages.count,
    last_activity_at: conversation.last_activity_at.to_i,
    contact_inbox: { source_id: conversation.contact_inbox.source_id }
  }
end
```

`conversation.contact_inbox.source_id` **não tem proteção contra `nil`**. `Conversation belongs_to
:contact_inbox` (`app/models/conversation.rb:105`) só é validado como obrigatório no momento de
salvar — não impede que a linha referenciada seja apagada depois. Confirmado em
`db/schema.rb:691`: a coluna `contact_inbox_id` **não tem constraint de foreign key no banco**,
então nada impede que fique "órfã" (apontando pra um `ContactInbox` que não existe mais).

Esse método é chamado a partir do partial jbuilder compartilhado
`app/views/api/v1/conversations/partials/_conversation.json.jbuilder` (linhas ~30-37 e ~57), **duas
vezes por conversa** (última mensagem e última mensagem não-automática) — e esse mesmo partial é
usado tanto por `GET /conversations` (`index.json.jbuilder`) quanto por `POST /conversations/filter`
(`filter.json.jbuilder`). Ou seja, **os dois sintomas relatados (aba "Minhas" e filtro "Agente
atribuído") têm a mesma causa raiz** — não são bugs diferentes.

### Por que só aparece na página 2+ e só pra essa agente

- Paginação em ambos os endpoints é Kaminari simples (`.page(current_page).per(25)`), ordenada por
  `last_activity_at desc` — sem paginação por cursor.
- O Jbuilder monta o array inteiro em memória antes de responder
  (`json.array! @conversations do |conversation| ... end`) — se a conversa de posição 15, por
  exemplo, estourar exceção, **nada foi enviado ainda pro cliente**, e a exceção sobe crua.
- Se **uma conversa específica** atribuída à Anna Beatriz tem `contact_inbox_id` órfão, ela só
  aparece quando a paginação alcança a posição dela na lista ordenada por atividade — por isso a
  página 1 funciona e a página 2 (ou além) quebra, consistentemente, só pra ela.

### Por que vira um 500 genérico, sem detalhe

`app/controllers/concerns/request_exception_handler.rb` só trata `ActiveRecord::RecordNotFound`,
`Pundit::NotAuthorizedError`, `ActionController::ParameterMissing` (e `ActiveRecord::RecordInvalid`
via `rescue_from` de classe) — **não existe nenhum rescue genérico pra `NoMethodError`/`StandardError`**.
Esse handler é registrado como `around_action` em `ApplicationController`, o que significa que ele
**envolve a renderização implícita do template Jbuilder também** — é o lugar certo pra adicionar um
log temporário que capture esse tipo de erro (diferente de um `rescue` dentro do método da action,
que não pegaria uma exceção lançada durante o render do template, que acontece depois que o método
da action retorna).

### Não é bug do módulo Kanban/Pipeline

Confirmado que o módulo Kanban/Pipeline **não tem nenhuma relação com esse bug** — nenhum jbuilder
de conversa referencia `PipelineItem`, e a única associação cruzada (`Contact has_many
:pipeline_items`) não é tocada pelo fluxo de listagem/filtro de conversas. É um problema latente do
Chatwoot "puro", pré-existente às mudanças do CRM.

Candidatos mais prováveis pra origem da referência órfã (Chatwoot core, não precisa investigar mais
agora, só contexto):
- `ContactInbox`/`Contact` usam `has_many ..., dependent: :destroy_async` — destruição assíncrona
  via job, existe uma janela real onde a linha pai já sumiu mas a conversa ainda aponta pra ela.
- `app/services/internal/remove_stale_contact_inboxes_service.rb` faz `ContactInbox.where(...).delete_all`
  — `DELETE` direto no banco, que não passa pelos callbacks do Rails.
- Confirmado que **não** vem de merge de contatos — `app/actions/contact_merge_action.rb` já
  repointa `contact_inbox`/`conversation` corretamente antes de destruir o contato mesclado.

### Confirmação: não é o mesmo bug já conhecido do filtro de data

Já existia um bug diagnosticado antes (`Date.iso8601` sem rescue em `app/services/filter_service.rb:29`,
ver `claude/tasks/23-chore-temp-log-conversations-filter-500.md`). Confirmado que **esse log nunca
foi de fato aplicado ao controller** (só ficou no arquivo de task) — e, mais importante, confirmado
via `lib/filters/filter_keys.yml:23-30` que `assignee_id` é `data_type: "text"`, não `"date"` — o
branch do `Date.iso8601` é **estruturalmente inalcançável** por um filtro de "Agente atribuído".
São dois bugs diferentes; esta task cobre o novo.

---

## Mudança 1 — Log de rede (rede de segurança) — `app/controllers/concerns/request_exception_handler.rb`

### Estado atual

```ruby
def handle_with_exception
  yield
rescue ActiveRecord::RecordNotFound => e
  ...
rescue Pundit::NotAuthorizedError => e
  ...
rescue ActionController::ParameterMissing => e
  ...
ensure
  Current.reset
end
```

### Mudança proposta

Adicionar um novo `rescue StandardError`, **depois** dos já existentes (Ruby avalia em ordem — os
três casos específicos continuam tratados exatamente como hoje, sem mudança nenhuma nesse caminho).
Esse rescue cobre qualquer request da aplicação (não só conversas) — é o ponto certo pra pegar erros
de renderização de view em qualquer controller, já que é um `around_action` e envolve o render
implícito do Jbuilder também:

```ruby
def handle_with_exception
  yield
rescue ActiveRecord::RecordNotFound => e
  # ...(sem mudança)
rescue Pundit::NotAuthorizedError => e
  # ...(sem mudança)
rescue ActionController::ParameterMissing => e
  # ...(sem mudança)
rescue StandardError => e
  # TEMP DEBUG (remover após diagnosticar o 500 no carregamento/filtro de conversas — Anna Beatriz)
  Rails.logger.error(
    "[REQUEST_DEBUG_TEMP] controller=#{controller_name}##{action_name} " \
    "account=#{Current.account&.id} user=#{Current.user&.id} " \
    "params=#{params.except(:controller, :action).to_unsafe_h} " \
    "error=#{e.class}: #{e.message}"
  )
  Rails.logger.error("[REQUEST_DEBUG_TEMP] backtrace:\n#{e.backtrace&.first(20)&.join("\n")}")
  raise
ensure
  Current.reset
end
```

`raise` sem argumento relança a exceção original — a resposta HTTP pro usuário continua sendo
exatamente o mesmo 500 de hoje. Nenhuma mudança de comportamento.

## Mudança 2 — Log cirúrgico no ponto suspeito — `app/models/message.rb`

Além do log genérico acima (confirma a exceção e o request, mas não isola qual conversa
especificamente), adicionar um log bem específico no método suspeito, pra identificar exatamente
qual `conversation_id` está com a referência quebrada:

### Estado atual

```ruby
def conversation_push_event_data
  {
    assignee_id: conversation.assignee_id,
    unread_count: conversation.unread_incoming_messages.count,
    last_activity_at: conversation.last_activity_at.to_i,
    contact_inbox: { source_id: conversation.contact_inbox.source_id }
  }
end
```

### Mudança proposta

```ruby
def conversation_push_event_data
  {
    assignee_id: conversation.assignee_id,
    unread_count: conversation.unread_incoming_messages.count,
    last_activity_at: conversation.last_activity_at.to_i,
    contact_inbox: { source_id: conversation_contact_inbox_source_id }
  }
end

private

def conversation_contact_inbox_source_id
  conversation.contact_inbox.source_id
rescue NoMethodError => e
  # TEMP DEBUG (remover após diagnosticar o 500 no carregamento/filtro de conversas — Anna Beatriz)
  Rails.logger.error(
    "[CONV_DEBUG_TEMP] conversation_id=#{conversation.id} " \
    "contact_inbox_id=#{conversation.contact_inbox_id} contact_id=#{conversation.contact_id} " \
    "error=#{e.message}"
  )
  raise
end
```

Isso aponta, no log, exatamente a conversa problemática (`conversation_id` + `contact_inbox_id`
órfão) — confirma a hipótese e já dá o suficiente pra decidir a correção de verdade depois.

**Por que essa abordagem dupla**: o log 1 (controller) é uma rede de segurança — confirma que é
esse tipo de erro mesmo (e não outra coisa que a leitura de código não previu) e mostra o backtrace
completo. O log 2 (model) é cirúrgico — se a hipótese estiver certa, aponta o `conversation_id`
exato sem precisar adivinhar ou rodar query manual em produção.

**Nota de implementação**: `Message` já pode ter uma seção `private` existente mais abaixo no
arquivo — adicionar `conversation_contact_inbox_source_id` lá, não criar uma segunda seção
`private` duplicada.

---

## Como aplicar e observar (ambiente Docker Swarm + Traefik)

Como o ambiente roda em Docker Swarm (não `docker compose` simples), os comandos de log mudam em
relação ao processo documentado em `claude/09-deploy-producao.md`:

1. Build/push da imagem com essas duas mudanças.
2. Deploy via `docker stack deploy` (em vez de `docker compose up -d`).
3. Descobrir o nome do serviço Rails: `docker service ls | grep rails` (formato
   `<nome_da_stack>_rails` ou parecido).
4. Acompanhar os logs em tempo real:
   ```bash
   docker service logs -f --since 10m <nome_da_stack>_rails | grep -E "REQUEST_DEBUG_TEMP|CONV_DEBUG_TEMP"
   ```
5. Reproduzir o problema: logar como Anna Beatriz, ir em "Minhas conversas", rolar até quebrar (ou
   aplicar o filtro "Agente atribuído = Anna Beatriz" e rolar).
6. Copiar as linhas de log — a linha `[CONV_DEBUG_TEMP] conversation_id=...` já deve apontar
   exatamente qual conversa está com o `contact_inbox_id` órfão.

---

## Depois de confirmado (não fazer agora)

Assim que o log confirmar a conversa/causa exata, avaliar duas frentes separadas (cada uma vira uma
task própria depois, só depois da confirmação):

1. **Correção pontual do bug de código**: proteger `conversation.contact_inbox.source_id` com `&.`
   (decidir o que enviar quando `nil` — provavelmente omitir a chave `contact_inbox` do payload
   nesse caso) em `app/models/message.rb`, e remover os dois logs temporários desta task.
2. **Correção do dado órfão**: identificar e corrigir (ou limpar) a(s) conversa(s) com
   `contact_inbox_id`/`contact_id` apontando pra registros inexistentes — possivelmente adicionar
   uma constraint de FK de verdade nessas colunas pra prevenir recorrência, e revisar
   `RemoveStaleContactInboxesService`/os `dependent: :destroy_async` que provavelmente causaram a
   orfandade.

---

## Verificação

1. Localmente: criar uma conversa de teste, apagar manualmente o `ContactInbox` associado via
   console Rails (`ContactInbox.find(x).delete` — sem callbacks, simulando o cenário real) mantendo
   a conversa, então acessar a listagem/filtro que a inclui — confirmar que aparecem os logs
   `[REQUEST_DEBUG_TEMP]` e `[CONV_DEBUG_TEMP]` com o `conversation_id` certo, e que a resposta HTTP
   continua sendo 500 (nenhuma mudança de comportamento, só o log é novo).
2. Confirmar que uma conversa/filtro sem esse problema continua funcionando normalmente — os novos
   rescues não devem interferir no caminho de sucesso nem nos erros já tratados
   (`RecordNotFound`/`Pundit`/`ParameterMissing`/`RecordInvalid`).
3. Deploy em produção conforme os passos acima, reproduzir com a conta da Anna Beatriz, e confirmar
   que os logs aparecem com o `conversation_id` real problemático.
