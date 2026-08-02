---
name: analise-viabilidade
description: Use quando o usuário pedir para analisar a viabilidade de implementar uma
  feature ou mudança antes de codar. Ativar em pedidos como "analisa a viabilidade de X",
  "vamos analisar se dá pra implementar Y", "quero avaliar Z antes de começar", "pode
  analisar essa implementação nova".
---

Você está em modo de análise, não de implementação. Ative o plan mode antes de qualquer
outra coisa — nenhuma edição de código de produção acontece nesta etapa, só investigação
e produção de um plano.

## O que investigar

1. **Código afetado**: mapeie todo o código que pode ser impactado pela mudança —
   models, controllers, services, listeners, frontend (components/store/routes), e
   se aplicável, verifique se há extensão correspondente em `enterprise/`
   (ver skill `sincronizar-enterprise` se existir no projeto).

2. **Padrões reutilizáveis**: procure ativamente por implementações parecidas já
   existentes no código antes de propor algo novo. O objetivo é modelar em cima do
   que já existe, não reinventar. Cite o arquivo que serve de referência para cada
   padrão encontrado.

3. **Riscos e imprevistos**: liste possíveis erros, bugs, edge cases ou efeitos
   colaterais que a mudança pode causar — race conditions, quebra de contrato com
   código dependente (ex. listeners, mods de enterprise, specs existentes), problemas
   de performance, ou impacto em multi-tenancy.

## O que entregar no plano

Ao final da investigação, apresente ao usuário um plano completo contendo:

- **O que precisa ser modificado ou adicionado** (arquivo por arquivo, ou área por área)
- **Padrões de código a seguir/reutilizar**, com referência ao arquivo original
- **Riscos e possíveis erros identificados**, com o motivo de cada um
- **Passo a passo de implementação**, ordenado, construído em cima dos achados acima

Não proponha o passo a passo antes de completar a investigação das três áreas acima.
O plano só é considerado completo quando cobre as três: código afetado, padrões
reutilizáveis, e riscos.

**Aguarde aprovação explícita do usuário sobre o plano antes de prosseguir.**

## Depois da aprovação

Quando o usuário aprovar o plano:

1. Crie os arquivos de task correspondentes ao passo a passo aprovado, seguindo o
   padrão de organização de tasks já usado no projeto (ex. pastas como
   `claude/<nome>_tasks/`, com um arquivo de visão geral e uma task por etapa —
   confira a estrutura de uma pasta `*_tasks/` existente antes de criar, para manter
   o mesmo formato).
2. **Não implemente nenhum código nesta etapa.** A entrega desta skill termina na
   criação das tasks. A implementação em si só começa quando o usuário pedir
   explicitamente para começar a executar uma task específica.