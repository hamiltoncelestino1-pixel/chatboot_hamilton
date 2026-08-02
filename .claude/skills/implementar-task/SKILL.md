---
name: implementar-task
description: Use quando o usuário pedir para começar a implementar uma task específica
  (geralmente já criada por uma análise de viabilidade prévia). Ativar em pedidos como
  "implementa a task X", "bora começar a task Y", "pode implementar isso agora",
  "executa a próxima task".
---

## Passo 1 — Ler a task completa

Antes de qualquer coisa, leia o arquivo da task inteiro (não só o título/resumo).
Se a task fizer parte de um conjunto (ex. `claude/<nome>_tasks/`), leia também o
arquivo de visão geral do conjunto para entender o contexto maior em que essa task
se encaixa.

## Passo 2 — Analisar os arquivos afetados

Mapeie e leia os arquivos reais que serão criados, modificados ou removidos por essa
task específica. Não assuma pelo texto da task — confirme no código atual como cada
arquivo está hoje antes de planejar a mudança.

## Passo 3 — Resumo e permissão

Apresente ao usuário um resumo objetivo do que vai ser feito: arquivos afetados e a
mudança em cada um. **Aguarde permissão explícita do usuário antes de prosseguir.**
Não pule para a implementação junto com o resumo.

## Passo 4 — Implementar

Só depois da permissão, implemente a task. Siga os padrões e convenções já
documentados no CLAUDE.md e nas skills relevantes do projeto (ex. fluxo de eventos,
endpoint de API, sincronização com enterprise/) conforme a natureza da mudança.

## Passo 5 — Testes

- Rode os testes automáticos relevantes para o que foi alterado.
- Monte uma lista de testes manuais para o usuário conferir a task (passo a passo
  do que verificar, incluindo caminho feliz e algum caso de borda relevante).
- Apresente o resultado dos testes automáticos e a lista de testes manuais ao
  usuário — a task só é considerada concluída depois dessa apresentação, não
  antes.