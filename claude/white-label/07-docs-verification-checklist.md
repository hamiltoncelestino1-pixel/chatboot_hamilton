# Task: Atualizar documentação e checklist final de QA

## Objetivo

Fechar o overhaul de white-label: atualizar o guia interno `claude/04-white-label.md`
(escrito para o rebrand da Mazza) para refletir a Noble Company, e rodar um checklist manual
completo cobrindo tudo que as tasks `01` a `06` tocaram.

Esta é a **última** task da sequência — depende de todas as anteriores estarem aplicadas.

---

## 1. Atualizar `claude/04-white-label.md`

O arquivo hoje é um guia conceitual genérico (não cita "Mazza" literalmente na maior parte,
mas foi escrito pensando nesse rebrand). Revisar e atualizar:

- Confirmar que a tabela de chaves de `installation_config.yml` continua precisa.
- Adicionar/atualizar o checklist de verificação no final do arquivo para refletir também os
  pontos novos cobertos nesta rodada (cor primária/auxiliar via `_noble-brand.scss` e
  `theme/colors.js`, não só logo/nome).
- Se fizer sentido, referenciar esta pasta (`claude/white-label/`) como o histórico de tasks
  do rebrand da Noble, para quem for whitelabel-ar de novo no futuro ter um exemplo real.

## 2. Checklist manual de verificação (rodar depois de `01`-`06` aplicadas)

- [ ] **Login/Signup**: novo logo (claro/escuro) e novo nome aparecem corretamente; fundo com
      acento roxo (task 06) visível.
- [ ] **Dashboard modo claro**: botões primários/outline usam o vermelho novo; nenhum resto de
      dourado (`#D4AF37`) visível.
- [ ] **Dashboard modo escuro**: mesma checagem, em `.dark`.
- [ ] **Ícone pequeno** (sidebar/header) usando `logo_thumbnail.svg` novo.
- [ ] **Widget real** embedado em uma página de teste: "Powered by Noble Company" com o
      thumbnail novo.
- [ ] **Preview do widget** no dashboard (`widget-preview`): consistente com o widget real.
- [ ] **Central de Ajuda / Portal** (se em uso): rodapé de branding atualizado.
- [ ] **Email transacional** (ex.: convite de agente): accent-bar, botão CTA e rodapé "This
      email was sent by Noble Company" no vermelho novo, sem dourado.
- [ ] **Super Admin → App Configs → Branding**: valores da Noble Company, editáveis.
- [ ] **Favicon** (aba do navegador) e `manifest.json` (nome/tema, se `DISPLAY_MANIFEST` for
      testado como `true` temporariamente).
- [ ] **i18n**: buscar por `Chatwoot` e `Mazza` nos arquivos tocados na task `05` — nenhuma
      ocorrência residual (fora do que foi decidido manter).
- [ ] **Labels/tags de contato**: cores roxo/violeta escolhidas pelo usuário continuam
      intactas (sem regressão da task `06`).
- [ ] `pnpm eslint` e `bundle exec rubocop -a` limpos.

---

## Verificação

O próprio checklist acima **é** a verificação desta task. Marcar cada item conforme testado
manualmente em ambiente de desenvolvimento (`pnpm dev` / `overmind start -f Procfile.dev`).
