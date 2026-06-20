# 10 — Fluxo de Git (trabalho em equipe)

Como a equipe trabalha em paralelo no `noble-company/chatwoot-noble` sem um pisar no
código do outro. Branch principal (tronco) = **`develop`**.

## Ideia central

A `develop` é a "fonte da verdade" — sempre estável e funcionando. **Ninguém commita
direto nela.** Cada tarefa acontece numa **branch** própria (um galho), isolada, e só volta
pra `develop` depois de revisada, via **Pull Request (PR)**.

```
develop  ●────●────●────────────●────  (tronco, sempre estável)
               \                 ↑
   feature       ●───●───●───────┘  (merge via Pull Request)
```

## Vocabulário

| Termo | O que é |
|---|---|
| **branch** | Linha de desenvolvimento isolada (um "galho") |
| **commit** | "Save point" com suas mudanças + mensagem descritiva |
| **push** | Enviar commits locais para o GitHub |
| **pull** | Trazer mudanças do GitHub para o seu PC |
| **merge** | Juntar uma branch em outra |
| **Pull Request (PR)** | Pedido de "juntar minha branch na develop" — onde o colega revisa |
| **conflito** | Os dois editaram a MESMA linha do MESMO arquivo; um humano decide |

## ✋ Antes de começar QUALQUER tarefa (checklist rápido)

Hábito obrigatório — **sempre confira em que branch você está e parta da `develop`
atualizada**, nunca comece a editar sem isso:

```bash
git branch --show-current      # 1. EM QUAL branch estou?
git checkout develop           # 2. volto pro tronco
git pull origin develop        # 3. atualizo (pego o que o colega já mergeou)
git checkout -b feature/minha-tarefa   # 4. crio a branch da tarefa
git branch --show-current      # 5. confirmo que estou na branch nova
```

Por que isso importa: se você começar a codar direto na `develop` (ou numa branch
antiga/errada), corre o risco de commitar no lugar errado, misturar tarefas e gerar
conflitos chatos. 30 segundos de verificação evitam horas de dor de cabeça.

## Fluxo do dia a dia

```bash
# 1. Sempre comece atualizando o tronco
git checkout develop
git pull origin develop

# 2. Crie sua branch a partir dele
git checkout -b feature/white-label        # uma pessoa
# git checkout -b feature/integracao-whatsapp   # a outra

# 3. Trabalhe e vá salvando em commits pequenos e coerentes
git add .
git commit -m "Troca logo e nome da marca na tela de login"

# 4. Envie sua branch pro GitHub
git push origin feature/white-label

# 5. Abra um Pull Request no GitHub: feature/white-label -> develop
#    O colega revisa, comenta e faz o merge.

# 6. Depois do merge, atualize o tronco local e comece a próxima tarefa (volta ao passo 1)
git checkout develop
git pull origin develop
```

## Convenção de nomes de branch

| Prefixo | Quando usar | Exemplo |
|---|---|---|
| `feature/` | funcionalidade nova | `feature/white-label` |
| `fix/` | correção de bug | `fix/upload-anexos` |
| `chore/` | infra/configuração/manutenção | `chore/docker-local-setup` |
| `docs/` | só documentação | `docs/guia-deploy` |

## Conflitos: como reduzir e resolver

Conflito = os dois mexeram na mesma linha do mesmo arquivo. Não é grave, o git só pede que
alguém decida. Para reduzir:

- **Combinem quem mexe em quê** (ex.: um no white-label, outro na integração — áreas
  diferentes = quase nunca conflita).
- **Atualize sua branch com a `develop` com frequência**, em vez de um conflitão no fim:
  ```bash
  git checkout feature/white-label
  git merge develop        # traz o que já entrou na develop pra sua branch
  ```

Quando o git marcar conflito, ele insere marcadores no arquivo:
```
<<<<<<< HEAD
   sua versão
=======
   versão da develop
>>>>>>> develop
```
Edite deixando só o que deve ficar, remova os marcadores, depois `git add` + `git commit`.

## Regras de ouro

1. **Nunca commitar direto na `develop`** — sempre branch + PR.
2. `git pull` antes de criar branch e antes de começar o dia.
3. **Uma tarefa = uma branch.**
4. Mensagens de commit claras (o quê e por quê).
5. **PRs pequenos** — mais rápidos e fáceis de revisar.
6. Nunca commitar **secrets** (`.env`, senhas, chaves) — o `.env` já está no `.gitignore`.
