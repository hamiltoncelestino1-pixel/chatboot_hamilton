# 07 — Camada Enterprise

A pasta `enterprise/` contém os recursos premium (pagos) do Chatwoot. Ela **espelha a
estrutura de `app/`** e é carregada por cima do código community.

## Estrutura

`enterprise/app/` repete as mesmas pastas do core:
```
enterprise/app/
  builders/  controllers/  dispatchers/  drops/  fields/
  finders/   helpers/      jobs/         listeners/
  mailers/   models/       policies/     presenters/
  services/  views/
```
Além de:
- `enterprise/config/` — configuração extra.
- `enterprise/lib/` — utilitários premium.
- `enterprise/LICENSE` — licença comercial (diferente do core, que é MIT/aberto).

## Como o carregamento funciona

O Rails adiciona `enterprise/` aos paths de autoload. Quando existe um arquivo enterprise
com o mesmo nome/namespace de um do core, ele **estende ou sobrescreve** o comportamento
(via `prepend`/módulos `Enterprise::...`).

## Implicações para nossa customização

- **Atenção a sobrescritas**: ao customizar algo do core, verifique se há um arquivo
  correspondente em `enterprise/` que altera aquele comportamento — senão a mudança pode
  não ter efeito (ou ter efeito diferente) na build enterprise.
- **Onde colocar features premium**: se a funcionalidade for exclusiva da nossa versão
  paga, o lugar natural é `enterprise/`. Recursos base ficam em `app/`.
- **Licenciamento**: o conteúdo de `enterprise/` está sob licença comercial. Considere
  isso ao redistribuir nossa versão personalizada.

## Exemplos de recursos tipicamente enterprise
- SLA e políticas de atendimento.
- Auditoria (audit logs).
- SSO/SAML.
- Recursos avançados do Captain (IA).
