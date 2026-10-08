# Task 23 — Fix: lacunas de tradução `pt_BR` no domínio CRM (Tasks, Pipeline, notificações)

Severidade: 🟠 Alta (impacto de produto, não de código). Achado durante a implementação da
task 20 (2026-10-05), a partir de uma observação do usuário de que "as tasks têm muita coisa
errada de tradução".

## Objetivo

A task 20 fechou **uma** chave (`PIPELINE_ITEM_STALE` em `pt_BR/settings.json`). Ao medir o
resto, apareceu uma lacuna muito maior: features inteiras deste fork — que **não existem no
Chatwoot original** e portanto nunca passaram por Crowdin — estão sem tradução nenhuma, e a
instalação é de um produto brasileiro.

Tudo abaixo foi **medido**, comparando conjuntos de caminhos de chave entre `en` e `pt_BR`.
Nada é estimativa.

## Lacunas medidas

### Frontend — `app/javascript/dashboard/i18n/locale/`

| Arquivo | Chaves em `en` | Faltando em `pt_BR` | O que isso significa na tela |
|---|---|---|---|
| `tasks.json` | 21 | **21 — o arquivo não existe em `pt_BR`** | A UI inteira de Tarefas aparece em inglês |
| `pipelineMgmt.json` | 79 | **30** | Ver detalhe abaixo |
| `settings.json` | 582 | 1 (`SIDEBAR.REPORTS_FUNNEL`) | Item de menu do relatório de funil em inglês |
| `kanban.json` | 119 | 0 ✅ | — |
| `macros.json` | 85 | 0 ✅ | — |
| `automation.json` | 163 | 2 | `ATTRIBUTES.COMPANY_NAME`, `LAST_RESPONDING_AGENT` — chaves do upstream, não do CRM |

Detalhe das 30 de `pipelineMgmt.json`:

- **27 chaves** = o bloco `PIPELINE_LOST_REASON_MGMT` **inteiro**. A tela de configuração de
  motivos de perda está 100% em inglês, incluindo títulos, botões, placeholders, mensagens de
  confirmação de exclusão e toasts de sucesso/erro.
- `PIPELINE_MGMT.AGENTS.SYNC_ASSIGNMENTS.TITLE` e `.DESCRIPTION`
- `PIPELINE_MGMT.LOST_REASONS_LINK`

**Total no frontend: 52 chaves** no domínio CRM (21 + 30 + 1).

### Backend — `config/locales/pt_BR.yml`

`en.yml` tem 356 chaves, `pt_BR.yml` tem 331 — **25 faltando**, das quais **9 são do domínio
CRM**:

```
notifications.notification_title.task_due
notifications.notification_title.pipeline_item_stale
notifications.task_due_body
notifications.pipeline_item_stale_body
errors.task.conversation_contact_mismatch
errors.task.pipeline_item_contact_mismatch
errors.pipeline_item.conversation_contact_mismatch
errors.pipeline_stage.cannot_delete_special_stage
errors.macros.execute.pipeline_item_ids_required
```

As 4 primeiras são as que o usuário vê com mais frequência: **título e corpo da notificação no
sininho e no push**, para tarefa vencendo e card parado.

**O `en.yml` está completo** (`notification_title.task_due` e `.pipeline_item_stale` em
`en.yml:251-252`, os dois `_body` em `:253-254`) — a lacuna é exclusivamente do `pt_BR`.

As outras 16 chaves faltando no `pt_BR.yml` são de domínios fora do CRM e ficam fora desta task.

## Decisão de produto necessária antes de implementar

O `CLAUDE.md` diz que a regra geral é editar **só** `en`, com exceção explícita de três arquivos
do domínio Kanban/Pipeline (`kanban.json`, `automation.json`, `macros.json`), que mantêm `pt_BR`
sincronizado à mão.

Os arquivos com lacuna aqui — `tasks.json`, `pipelineMgmt.json`, e o `pt_BR.yml` do backend —
**não estão nessa lista de exceção**, mas são features 100% próprias deste fork: não vão chegar
pelo Crowdin nunca, porque não existem no upstream. Ou seja, a regra geral não se aplica a eles
na prática; ela só faz sentido para conteúdo que a comunidade traduz.

**A decisão a tomar:** ampliar formalmente a lista de exceção do `CLAUDE.md` para "todo domínio
próprio do fork mantém `en` + `pt_BR`", em vez de enumerar três arquivos. Isso evita que a
próxima feature nova nasça com a mesma lacuna.

## O que corrigir

1. Criar `app/javascript/dashboard/i18n/locale/pt_BR/tasks.json` com as 21 chaves traduzidas,
   espelhando a estrutura de `en/tasks.json`. **Conferir se precisa ser registrado** em
   `i18n/locale/pt_BR/index.js` (o `en` provavelmente já registra; checar antes de assumir).
2. Completar as 30 chaves de `pt_BR/pipelineMgmt.json`.
3. Acrescentar `SIDEBAR.REPORTS_FUNNEL` em `pt_BR/settings.json`.
4. Acrescentar as 9 chaves de domínio CRM em `config/locales/pt_BR.yml`, preservando as
   interpolações (`%{task_title}`, `%{item_title}`, `%{due_date}`, `%{days}`) — uma interpolação
   traduzida ou omitida quebra a mensagem em runtime.
5. Atualizar a seção de i18n do `CLAUDE.md` conforme a decisão acima.

Terminologia já estabelecida no `pt_BR/kanban.json`, a seguir para manter consistência: **"card"**
(não "cartão") e **"Pipeline"** (não "funil", exceto no nome próprio "Funil de Vendas").

## Testes

Com o locale `pt_BR` ativo:

1. Abrir a tela de Tarefas — nenhum texto em inglês, nenhuma chave crua.
2. Configurações → Pipelines → Motivos de perda — tela inteira em português, incluindo o modal
   de confirmação de exclusão e os toasts.
3. Receber uma notificação de tarefa vencendo e uma de card parado — título e corpo em
   português no sininho, com a data/contagem de dias interpolada corretamente.
4. Disparar um erro de validação de Task (ex. vincular conversa de outro contato) e conferir a
   mensagem em português.

Atenção ao sintoma: sem a chave, o vue-i18n cai no fallback `en` (o `createI18n` em
`i18n/instance.js:8-12` não define `fallbackLocale`, então ele usa o valor de `locale`, `'en'`).
Então o defeito aparece como **texto em inglês**, não como chave crua — é mais fácil de passar
despercebido numa revisão rápida.

## Critério de pronto

- Zero chaves do domínio CRM faltando em `pt_BR`, verificado pela mesma comparação de conjuntos
  de caminhos que produziu a tabela acima (não por inspeção visual).
- Interpolações preservadas em todas as mensagens do backend.
- `CLAUDE.md` atualizado com a regra decidida, para a próxima feature não repetir a lacuna.

## Resultado (2026-10-07)

### Correção à medição desta própria task: eram 63 chaves, não 52

A tabela de "Lacunas medidas" acima classificou `report.json` como arquivo do upstream e não
olhou dentro dele. **As 11 chaves faltantes lá são o bloco `FUNNEL_REPORTS` inteiro** — o
relatório de funil é feature exclusivamente nossa, e a tela estava 100% em inglês. O erro veio
de medir por arquivo em vez de por namespace. Total real no frontend: **63** (21 + 30 + 1 + 11).

Também apareceram **2 chaves de backend** que a lista original não pegou:
`errors.macros.execute.conversation_ids_required` e `errors.macros.execute.stage_not_found`.
Elas ficaram de fora porque o filtro que usei na medição era
`grep -i 'notification|task|pipeline'`, e nenhum dos dois nomes casa com isso. Total real no
backend: **11**, não 9.

Lição: filtrar por palavra-chave no nome da chave perde itens. A varredura final usa
comparação de conjuntos completa e depois filtra, o que é confiável.

### O que foi feito

| Arquivo | Mudança |
|---|---|
| `pt_BR/tasks.json` | **arquivo novo**, 21 chaves |
| `pt_BR/index.js` | `import tasks` + `...tasks` — **sem isso o arquivo novo é ignorado em silêncio** |
| `pt_BR/pipelineMgmt.json` | 30 chaves (bloco `PIPELINE_LOST_REASON_MGMT` inteiro + `SYNC_ASSIGNMENTS` + `LOST_REASONS_LINK`) |
| `pt_BR/report.json` | 11 chaves — bloco `FUNNEL_REPORTS` inteiro |
| `pt_BR/settings.json` | `SIDEBAR.REPORTS_FUNNEL` = "Funil" |
| `config/locales/pt_BR.yml` | 11 chaves: 4 de notificação + 7 de erro |
| `CLAUDE.md` | regra de i18n reescrita (ver abaixo) |

### Uma colisão de chave YAML que quase passou

O bloco `errors.pipeline_item` que escrevi não funcionou de primeira: **já existia** um
`pipeline_item:` mais abaixo no `errors:` do `pt_BR.yml` (com 4 chaves), e em YAML a última
definição vence — a minha foi silenciosamente descartada. Só apareceu porque a verificação
contou 8 chaves novas quando eu havia escrito 9. Corrigido fazendo merge no bloco existente em
vez de criar um segundo.

Vale como aviso: `grep` por uma chave antes de adicionar um bloco em YAML, porque duplicata não
dá erro — dá perda silenciosa.

### Decisão de produto tomada

A regra do `CLAUDE.md` passou de "exceção são estes três arquivos" para **"todo domínio próprio
do fork mantém `en` + `pt_BR`"**, com o critério explícito ("é feature nossa?") valendo acima da
lista de arquivos. Motivo: `tasks.json`, `pipelineMgmt.json` e `FUNNEL_REPORTS` nasceram sem
tradução **justamente porque** a regra enumerava arquivos — nenhum deles estava na lista, e
nenhum deles jamais chegaria pelo Crowdin, porque não existe no upstream.

Acrescentado também o aviso sobre registrar arquivo de locale novo no `index.js`, que foi
exatamente a armadilha do `tasks.json`.

### Verificação

Comparação completa de conjuntos de caminhos de chave, `en` contra `pt_BR`:

```
=== dominio CRM (frontend) ===
tasks.json           en=21   faltando=0   OK
pipelineMgmt.json    en=79   faltando=0   OK
report.json          en=317  faltando=0   OK
settings.json        en=582  faltando=0   OK
kanban.json          en=119  faltando=0   OK
macros.json          en=85   faltando=0   OK

=== varredura geral ===
TOTAL faltando no frontend: 84  (era 147)
Ainda faltando com cara de dominio CRM: 0

=== backend ===
pt_BR.yml: 342 chaves (era 331) | faltando vs en: 14 (era 25)
faltando do dominio CRM: NENHUMA
```

As 84 restantes no frontend e as 14 no backend são **todas** de domínios herdados do upstream
(`helpCenter`, `onboarding`, `inboxMgmt`, `mfa`, `conversation`, `chatlist`, `contact`, as 2 de
`automation.json`, e no backend `captain`, `portals`, `voice`, `super_admin`, whatsapp) — fora
do escopo desta task por decisão explícita, e sujeitas à regra geral (Crowdin).

**Interpolações conferidas uma a uma** nas 4 mensagens de notificação:

```
task_due             en=['task_title'] pt=['task_title'] OK
pipeline_item_stale  en=['item_title'] pt=['item_title'] OK
task_due_body        en=['due_date']   pt=['due_date']   OK
pipeline_item_stale_body en=['days']   pt=['days']       OK
```

**Verificação em runtime no Rails** — as 11 chaves do backend resolvidas de verdade, com
interpolação:

```
locales carregados incluem pt_BR? true
task_due                       A tarefa "Ligar para o cliente" está vencendo
pipeline_item_stale            O card "Proposta ACME" está parado
task_due_body                  Vence 07/10/2026
pipeline_item_stale_body       Sem mudança de estágio há 12 dias
conversation_contact_mismatch  A conversa não pertence ao contato da tarefa.
pipeline_item_contact_mismatch O card do pipeline não pertence ao contato da tarefa.
conversation_contact_mismatch  A conversa não pertence ao contato vinculado
cannot_delete_special_stage    Este estágio é obrigatório e não pode ser excluído
pipeline_item_ids_required     pipeline_item_ids é obrigatório para executar uma macro de pipeline
conversation_ids_required      conversation_ids é obrigatório para executar uma macro de conversa
stage_not_found                stage_id não existe ou você não tem acesso ao pipeline dele
--- chaves com problema: 0 (esperado 0) ---
```

O script também compara cada valor com o `en` e acusaria se alguma tradução tivesse ficado
idêntica ao inglês por descuido — nenhuma ficou.

Detalhe que custou uma execução: o símbolo do locale é **`:pt_BR`** (underscore), não
`:'pt-BR'`. Com o hífen, `I18n` levanta `InvalidLocale`.

**Lint/formato:** `prettier --check` limpo nos 5 arquivos JSON/JS, `eslint` exit 0 no
`index.js`, `pt_BR.yml` parseia como YAML válido e está em LF (o `HEAD` também).

**Specs:** `useLocale.spec.js` **17/17**; `switch_locale_spec.rb` + `spec/jobs/notification/`
**22 examples, 0 failures**.

### Achado fora do escopo, registrado como task 24

A verificação em runtime expôs que **nenhuma** mensagem padrão do Rails existe para o nosso
locale: `errors.messages.blank`, `date.formats.default` e `number.currency.format.unit` todas
ausentes em `pt_BR`. A gem `rails-i18n 7.0.10` está instalada e tem `pt-BR.yml`, mas o locale da
aplicação é `pt_BR` (underscore, `languages.rb:21`) e o da gem é `pt-BR` (hífen) — `:'pt-BR'`
não entra em `available_locales`, então o conteúdo é inalcançável.

Em produção o `config.i18n.fallbacks` disfarça (cai para inglês); em development aparece
literalmente `"Translation missing. Options considered were: ..."`. É a mesma classe de problema
desta task, uma camada abaixo, mas atinge a aplicação **inteira** e não só o CRM.

Medido e registrado em [task 24](24-fix-locale-pt-br-nao-carrega-rails-i18n.md).

### Terminologia adotada

`card` (não "cartão"), `Pipeline` (não "funil" — exceto `FUNNEL_REPORTS.HEADER` = "Funil", que é
o nome da tela), `estágio` para stage, `responsável` para assignee. Consistente com o
`pt_BR/kanban.json`, que já era o arquivo de referência.

Nota de inconsistência pré-existente que **não** foi alterada: o bloco `errors.pipeline_item` já
existente no `pt_BR.yml` trata "pipeline" como palavra feminina ("à pipeline de destino", "a
stage selecionada"). Deixei como estava para não misturar uma mudança de redação de mensagens em
produção com esta task; as chaves novas usam o masculino, que é o padrão do resto do projeto.
