# Task 24 — Fix: o locale `pt_BR` não carrega as traduções padrão do Rails (`rails-i18n`)

Severidade: 🟠 Alta (impacto de produto em toda a aplicação, não só no domínio CRM). Achado
durante a verificação da task 23 (2026-10-07).

## Objetivo

A task 23 fechou as 74 chaves de `pt_BR` do domínio CRM. Ao verificar em runtime, a mensagem
padrão de validação de presença apareceu assim:

```
I18n.t('errors.messages.blank', locale: :pt_BR)
-> "Translation missing. Options considered were:
    - pt_BR.activerecord.errors.models.task.attributes.title.blank
    - pt_BR.activerecord.errors.models.task.blank
    - pt_BR.activerecord.errors.messages.blank
    - pt_BR.errors.attributes.title.blank
    - pt_BR.errors.messages.blank"
```

Ou seja: **nenhuma** mensagem padrão do Rails/ActiveRecord existe para o nosso locale pt_BR.
Medido:

```
errors.messages.blank       em pt_BR -> AUSENTE   | em en -> "can't be blank"
date.formats.default        em pt_BR -> AUSENTE
number.currency.format.unit em pt_BR -> AUSENTE
```

> **⚠️ O diagnóstico original desta task estava incompleto.** A seção "Causa raiz" abaixo
> atribui o problema ao descasamento `pt_BR` (underscore) × `pt-BR` (hífen). Isso é **metade** da
> causa, e não a principal: a gem estava limitada a `[:pluralization]`, então **nenhum** arquivo
> de locale dela carregava — para locale nenhum, não só pt_BR. A análise correta e completa está
> em `## Resultado`, no fim do arquivo. Mantenho o texto original para registro do que foi
> medido na primeira passada.

## Causa raiz (medida — ver ressalva acima)

A gem **está** instalada e **tem** o arquivo:

```
Gemfile:88        gem 'rails-i18n', '~> 7.0'
Gemfile.lock:731  rails-i18n (7.0.10)
/gems/.../rails-i18n-7.0.10/rails/locale/  ->  pt-BR.yml   pt.yml
```

Mas o locale que a aplicação usa é `pt_BR` com **underscore**, e o da gem é `pt-BR` com
**hífen** (a forma IETF):

```ruby
# config/initializers/languages.rb:21
16 => { name: 'Português Brasileiro (pt-BR)', iso_639_3_code: '', iso_639_1_code: 'pt_BR', enabled: true },

# config/initializers/languages.rb:49
Rails.configuration.i18n.available_locales = LANGUAGES_CONFIG.map { |_index, lang| lang[:iso_639_1_code].to_sym }
```

Resultado confirmado em runtime:

```
I18n.available_locales.grep(/pt/i)  ->  [:pt, :pt_BR]
:'pt-BR' disponivel?                ->  false
```

O `pt-BR.yml` da gem é carregado pelo load path mas o locale não entra em `available_locales`,
então na prática o conteúdo dele é inalcançável. É uma escolha de nomenclatura herdada do
upstream (todos os 58 locales usam underscore: `zh_TW`, `pt_BR`, etc.), **não** algo que este
fork introduziu.

## O que o usuário vê

Depende do ambiente, e é importante não confundir os dois:

| Ambiente | `config.i18n.fallbacks` | Backend | Sintoma |
|---|---|---|---|
| development | não definido (`nil`) | `I18n::Backend::Simple`, **sem** módulo `Fallbacks` | literalmente `"Translation missing. Options considered were: ..."` na tela |
| production / staging | `[I18n.default_locale]` (`production.rb:64`, `staging.rb:57`) | Rails inclui `I18n::Backend::Fallbacks` no boot | cai para **inglês** |

Confirmado em dev por inspeção do backend:

```
backend: I18n::Backend::Simple
inclui Fallbacks? false
```

Então em produção não é um texto quebrado — é a aplicação **meio em inglês** para o usuário
brasileiro: toda mensagem de erro de validação do ActiveRecord, formato de data, formato de
número e de moeda. Mesma classe de problema da task 23, uma camada abaixo e com alcance muito
maior (atinge a aplicação inteira, não só o CRM).

## O que corrigir

Três caminhos, em ordem da minha recomendação:

1. **Configurar o fallback de locale para apontar `pt_BR` → `pt-BR` → `en`** (e o equivalente
   para `zh_TW`, que tem o mesmo problema — **a confirmar** se a gem traz `zh-TW`). Assim o
   conteúdo da gem passa a ser alcançável sem renomear nada nem mexer no que o usuário
   seleciona. Precisa valer em **todos** os ambientes, não só produção, senão o dev continua
   mostrando "Translation missing" e o bug segue invisível em desenvolvimento.
2. Acrescentar `:'pt-BR'` em `available_locales` junto com `:pt_BR`. Mais simples, mas não
   resolve por si: o locale ativo da sessão continua sendo `pt_BR`, então ainda é preciso o
   fallback do item 1 para a busca chegar no `pt-BR`.
3. Copiar as chaves necessárias da gem para o nosso `config/locales/pt_BR.yml`. **Não
   recomendado**: duplica conteúdo mantido por terceiros e desatualiza a cada upgrade da gem.

Antes de implementar, **verificar quais outros locales têm o mesmo descasamento** — a lista de
`languages.rb` usa underscore em todos os códigos regionais, então provavelmente não é só o
pt_BR. Isso muda o tamanho da correção: se for geral, o fix certo é no mapeamento de fallback
para todos, não caso a caso.

## Testes

```ruby
# Deve devolver a mensagem em portugues, nao "Translation missing" nem ingles:
I18n.t('errors.messages.blank', locale: :pt_BR)
I18n.l(Date.current, locale: :pt_BR)
I18n.t('number.currency.format.unit', locale: :pt_BR)
```

Na UI, com o idioma da conta em Português Brasileiro: submeter um formulário com campo
obrigatório vazio (ex. criar uma Task sem título pela API/UI) e confirmar que a mensagem de erro
vem em português.

Testar **em development**, que hoje é o ambiente onde o defeito aparece pior (sem fallback).

## Critério de pronto

- `I18n.t('errors.messages.blank', locale: :pt_BR)` devolve português.
- Formatos de data e número resolvem em pt_BR.
- Nenhum `"Translation missing"` visível em development para pt_BR.
- Levantado (e corrigido ou registrado) se outros locales regionais têm o mesmo descasamento.

## Resultado (2026-10-07)

### A causa raiz era outra (e maior)

O descasamento underscore/hífen é real, mas **secundário**. A causa principal:

```ruby
# config/application.rb:40 (antes)
config.rails_i18n.enabled_modules = [:pluralization]
```

A gem estava limitada a pluralização. Medido no load path: **111 arquivos `.rb` de
`rails/pluralization/`, zero `.yml` de `rails/locale/`**. Ou seja, o conteúdo de locale da gem
(`date`, `number`, `activerecord`, `errors.messages`) **não carregava para locale nenhum** — não
era um problema do pt_BR:

```
fr     date=NAO  number=NAO  activerecord=NAO  errors.messages.blank=nil
de     date=NAO  number=NAO  activerecord=NAO  errors.messages.blank=nil
es     date=NAO  number=NAO  activerecord=NAO  errors.messages.blank=nil
pt     date=NAO  number=NAO  activerecord=NAO  errors.messages.blank=nil
pt_BR  date=NAO  number=NAO  activerecord=NAO  errors.messages.blank=nil
en     date=sim  number=sim  activerecord=sim  errors.messages.blank="can't be blank"
```

O `en` parecia completo e mascarou o problema — mas aquilo vem dos defaults do próprio Rails,
não da gem.

A linha veio do **upstream**: commit `0920a01e6`, Sojan Jose, PR #14266
("fix(i18n): align pluralization with locale rules"). Foi escolha deliberada deles de usar a gem
só pelas regras de pluralização. Este fix **diverge dessa decisão**, com aprovação do usuário.

Como o diagnóstico inicial errou: eu olhei só o pt_BR, vi que `:'pt-BR'` não estava em
`available_locales`, e parei aí — sem checar se o `fr` (correspondência exata, sem descasamento
nenhum) tinha o mesmo sintoma. Tinha. Um único caso de controle teria evitado a conclusão errada.

### O fix, em três camadas

Cada uma é necessária; provei isoladamente que nenhuma resolve sozinha.

| # | Arquivo | Mudança |
|---|---|---|
| 1 | `config/application.rb` | `enabled_modules = [:locale, :pluralization]` — sem isso nenhum `.yml` da gem entra no load path. Resolve sozinho os 36 locales de correspondência exata. |
| 2 | `config/initializers/languages.rb` | `:'pt-BR'`, `:'zh-TW'`, `:'zh-CN'` acrescentados a `available_locales` via `LOCALE_ALIASES_FOR_RAILS_I18N`. Com `enforce_available_locales: true`, o `I18n::Backend::Simple#store_translations` **descarta em silêncio** dados de locale fora da lista. São alias de lookup: **não** entram no `LANGUAGES_CONFIG`, então não viram idioma selecionável. |
| 3 | `config/application.rb` + `environments/production.rb` + `environments/staging.rb` | `config.i18n.fallbacks = [:en, { pt_BR: :'pt-BR', zh_TW: :'zh-TW', zh_CN: :'zh-CN' }]`. O `I18n::Locale::Fallbacks` deriva os pais quebrando por **hífen** — `pt_BR` não tem hífen, então não deriva nada. Os dois arquivos de ambiente precisam da mesma linha porque atribuem `config.i18n.fallbacks` depois do `application.rb` e descartariam o mapa. |

Dos 40 locales do app, só **4** não têm correspondência exata na gem: `pt_BR`, `zh_TW`, `zh_CN`
(os três cobertos pelo alias + fallback) e `no`, que a gem simplesmente não tem (ela traz
`nb`/`nn`) — fora do alcance deste fix.

### Verificação

Config ativa:

```
enabled_modules: #<Set: {:locale, :pluralization}>
arquivos da gem no load_path: .rb=111 .yml=121   (antes: .yml=0)
pastas: ["locale", "pluralization"]
:"pt-BR" em available_locales? true
backend tem Fallbacks? true
cadeia pt_BR: [:pt_BR, :"pt-BR", :pt, :en]
```

Sintomas, todos em `pt_BR`:

| | antes | depois |
|---|---|---|
| `errors.full_messages` (o que a API devolve) | `"Account Translation missing. Options considered were:\n- pt_BR.activerecord..."` | `["Account é obrigatório(a)", "Contact é obrigatório(a)"]` |
| `errors.messages.blank` | AUSENTE | `"não pode ficar em branco"` |
| `I18n.l(format: :short)` | levanta `MissingTranslationData` | `07 de outubro, 12:10` |
| `I18n.l(format: '%B')` | `"Translation missing: pt_BR.date.month_names"` | `outubro` |
| `number_to_currency(1234.5)` | `$1,234.50` | `R$ 1.234,50` |

Outros locales, que o fix alcança de passagem:

```
fr    "doit être rempli(e)"
de    "muss ausgefüllt werden"
es    "no puede estar en blanco"
zh_TW "不能為空白"
```

Nada regrediu no `en` (`"can't be blank"`, `$1,234.50`), as chaves próprias da
[task 23](23-fix-i18n-pt-br-dominio-crm.md) continuam resolvendo, e a lista de idiomas
selecionáveis continua com **40** entradas — os 3 alias ficaram fora dela, como previsto.

**Risco de override conferido antes de ligar o módulo:** nenhum arquivo em `config/locales/*.yml`
define `date:`, `number:`, `activerecord:` ou `time:` no topo, então o conteúdo da gem não
sobrescreve nada nosso.

**Specs:** `switch_locale_spec` + `spec/jobs/notification/` + `notification_spec` + `spec/drops/`
= **61 examples, 0 failures**. `rubocop` limpo nos arquivos tocados.

### Lacuna que permanece, de propósito

Os **nomes de atributo** seguem em inglês ("Account é obrigatório(a)", não "Conta"). Isso é
`activerecord.attributes.*`, que a gem não preenche — teria que ser traduzido modelo a modelo
no nosso `pt_BR.yml`. Fora do escopo: é um trabalho de catálogo, não um defeito de configuração,
e a mensagem já fica compreensível.
