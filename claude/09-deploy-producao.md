# 09 — Deploy em Produção

Como levar nossa versão customizada para um servidor. **Resumo**: customiza local →
testa no Docker dev → commita no nosso repo → CI builda a imagem → servidor faz pull.

## Repositório: usamos o NOSSO, não outro

O `origin` já é **`github.com/noble-company/chatwoot-noble`**. É nele que customizamos e
versionamos. **Não criar um repo "diferente"** — isso perderia histórico e a capacidade de
puxar atualizações do Chatwoot oficial.

### Manter-se atualizado com o Chatwoot oficial (opcional, recomendado)
```bash
git remote add upstream https://github.com/chatwoot/chatwoot.git
git fetch upstream
git merge upstream/develop   # ou a tag/branch desejada, resolvendo conflitos
```

## Modelo mental

O Chatwoot **não roda puxando código do git no servidor** — roda como **imagem Docker**:

```
nosso código (repo) → build da imagem → push pro registry → servidor faz pull e roda
```

⚠️ **Ponto de atenção**: o `docker-compose.production.yaml` aponta hoje para
`image: chatwoot/chatwoot:latest` — a **imagem oficial, SEM nossas customizações**.
Precisamos trocar para a **nossa imagem**.

## Passo a passo

### 1. Buildar e publicar a NOSSA imagem

**Automático (recomendado)**: o repo já tem o workflow `.github/workflows/publish_foss_docker.yml`
(e `publish_ee_docker.yml` para a versão enterprise). Ajustar o destino para o nosso
registry — ex.: GitHub Container Registry `ghcr.io/noble-company/chatwoot-noble`. A cada
push/tag ele builda e publica.

**Manual (para testar)**:
```bash
docker build -f docker/Dockerfile -t ghcr.io/noble-company/chatwoot-noble:latest .
docker push ghcr.io/noble-company/chatwoot-noble:latest
```

### 2. Apontar o compose de produção para a nossa imagem

No `docker-compose.production.yaml`:
```yaml
# de:
image: chatwoot/chatwoot:latest
# para:
image: ghcr.io/noble-company/chatwoot-noble:latest
```

### 3. No servidor: pull + migrar + subir
```bash
docker compose -f docker-compose.production.yaml pull
docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails db:chatwoot_prepare
docker compose -f docker-compose.production.yaml up -d
```

## Diferenças críticas vs. ambiente local

| Item | Local (dev) | Produção |
|---|---|---|
| `RAILS_ENV` | `development` | `production` |
| `.env` | valores de teste | **secrets reais** (NÃO vai pro git — está no `.dockerignore`) |
| `SECRET_KEY_BASE` | qualquer hex | hex forte e fixo |
| `FRONTEND_URL` | `localhost:3000` | domínio real (https) |
| SMTP | mailhog | provedor real (SES, Sendgrid, etc.) |
| `POSTGRES_PASSWORD` | vazio (`trust`) | **senha forte** |
| Dados do Postgres | efêmeros | **volume persistente** |
| Frente | — | **Nginx + SSL** (ver `deployment/nginx_chatwoot.conf`) |

## Migrar o banco a cada deploy

Sempre rodar `db:chatwoot_prepare` (aplica as migrations novas) antes de trocar os
containers de versão.

## Alternativa sem Docker (VM/bare-metal)

A pasta `deployment/` traz unidades **systemd** (`chatwoot-web`, `chatwoot-worker`),
config de **Nginx** e scripts de setup (`setup_20.04.sh`). É o caminho para rodar direto
numa VM Ubuntu, sem containers. Para nós, o caminho Docker acima costuma ser mais simples.

---

## ✅ Checklist antes do primeiro deploy

- [ ] Correções de ambiente commitadas no repo (CRLF dos entrypoints, `POSTGRES_HOST_AUTH_METHOD`,
      arquivos restaurados) — senão a imagem de produção sai quebrada. Ver [08-ambiente-local-docker.md](08-ambiente-local-docker.md).
- [ ] `publish_foss_docker.yml` apontando para o nosso registry.
- [ ] `docker-compose.production.yaml` usando a nossa imagem.
- [ ] `.env` de produção criado no servidor (secrets reais).
- [ ] Volume persistente configurado para o Postgres.
- [ ] Nginx + SSL na frente.
- [ ] `db:chatwoot_prepare` no fluxo de deploy.
