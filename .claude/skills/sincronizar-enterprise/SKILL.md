---
name: sincronizar-enterprise
description: Use depois de editar um arquivo em app/ (model, controller, service, policy, etc.) deste projeto, para checar se existe uma extensão correspondente em enterprise/ que também precisa de ajuste. Ativar quando o pedido envolver "isso afeta o enterprise?", "preciso atualizar a versão enterprise", "prepend_mod_with", "include_mod_with", ou sempre que uma mudança tocar lógica core que pode ter uma extensão em enterprise/app/.
---

# Sincronizar mudanças core com enterprise/

**Enquadramento**: `enterprise/` aqui é código nosso normal, já todo liberado neste projeto —
não é uma camada de licença/plano a proteger. O objetivo desta skill é evitar **bug silencioso
de dessincronia** (ex. um método renomeado que uma extensão dependia via `super`), não
gatekeeping de feature.

Código completo dos pares core/enterprise e do mecanismo de injeção:
[references/exemplos-pares.md](references/exemplos-pares.md)

## Como o mecanismo funciona

`prepend_mod_with`/`include_mod_with`/`extend_mod_with` são definidos em
`config/initializers/01_inject_enterprise_edition_module.rb` e injetados em **todo** `Module`
via `Module.prepend(InjectEnterpriseEditionModule)` — por isso qualquer classe do projeto pode
chamar `Foo.prepend_mod_with('Foo')`. Internamente, `each_extension_for` resolve o constante
`Enterprise::<nome>` (via `ChatwootApp.extensions`, que retorna `['enterprise']` numa
instalação normal) e, se existir, faz `prepend`/`include`/`extend` nele.

**Convenção de path** (confirmada lendo o código, não suposição): dado
`app/<camada>/<...caminho...>/foo.rb` terminando com `Foo.prepend_mod_with('Foo')`, a
extensão correspondente fica em `enterprise/app/<camada>/enterprise/<...caminho...>/foo.rb`
definindo `module Enterprise::Foo`. Isso funciona porque `config/application.rb` registra
cada subpasta de `enterprise/app/**` como raiz de autoload separada — então
`enterprise/app/models/enterprise/account.rb` mapeia pro constante `Enterprise::Account`.

Padrão de `prepend`: o método da extensão roda primeiro e decide se chama `super` pra versão
core — ex. `Enterprise::ReportPolicy#view?` chama
`@account_user.custom_role&.permissions&.include?('report_manage') || super`.

## Passo a passo prático

Dado um arquivo que você acabou de editar em `app/<camada>/<caminho>/foo.rb`:

1. **Grep no próprio arquivo** por `prepend_mod_with|include_mod_with|extend_mod_with` — se
   tiver, ele já diz o nome exato do constante a procurar (não precisa adivinhar):
   ```bash
   grep -n "prepend_mod_with\|include_mod_with\|extend_mod_with" app/<caminho>/foo.rb
   ```

2. **Se o arquivo core não tem nenhuma dessas chamadas**: esta skill não se aplica a ele —
   não é obrigatório adicionar isso proativamente, é decisão de produto. Pare aqui.

3. **Se tem**, monte o path esperado da extensão —
   `enterprise/app/<camada>/enterprise/<caminho>/foo.rb` — e confira se existe:
   - **Existe**: leia o módulo `Enterprise::Foo`. Como ele é `prepend`ado, geralmente
     sobrescreve método(s) específico(s) e dá `super`. Confira se a mudança que você fez não
     quebra esse contrato:
     - renomeou/removeu um método que a extensão sobrescreve ou chama via `super`?
     - mudou a assinatura (parâmetros) de um método que a extensão também define?
     - mudou o comportamento que a extensão espera antes/depois do `super`?
     Se sim, ajuste os dois lados.
   - **Não existe**: nada pra sincronizar agora — ok seguir.

## Duas ressalvas pra não gerar falso positivo

- **Nem todo arquivo em `enterprise/app/` é uma extensão de algo em `app/`.** Boa parte é
  modelo/serviço **novo, exclusivo do enterprise**, sem correspondente em `app/` (ex.
  `enterprise/app/models/account_saml_settings.rb`, `call.rb`, `company.rb`,
  `custom_role.rb` — sem arquivo irmão em `app/models/`). Só vale investigar quando o arquivo
  **core** que você mexeu já tem a chamada `prepend_mod_with`/`include_mod_with`.
- **Nem toda subpasta de `app/` tem espelho em `enterprise/app/` hoje.** Confirmado que
  `actions`, `assets`, `channels`, `dashboards`, `javascript`, `mailboxes` não têm overlay
  atualmente (só existem do lado core). Não assuma que uma camada tem extensão só porque
  outras têm.

## Checklist final

- [ ] `grep` no arquivo editado por `prepend_mod_with|include_mod_with|extend_mod_with`
- [ ] Se achou: montei o path enterprise esperado e chequei se existe
- [ ] Se existir: li o módulo e confirmei que a mudança não quebra o contrato (nomes/
      assinatura de método usados via `super`)
- [ ] Se não existir, ou o core não tiver a chamada: nenhuma ação necessária
