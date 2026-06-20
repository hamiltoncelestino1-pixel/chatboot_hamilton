# 08 — Ambiente Local (Docker)

Como rodar o Chatwoot Noble localmente no Docker, e os problemas (gotchas) que já
enfrentamos e resolvehos — para não repetir o esforço no futuro.

## Pré-requisitos

- **Docker Desktop** (com WSL2 no Windows).
- **RAM**: o Chatwoot é pesado. Em PCs de 16 GB, **limite a RAM do WSL2** (ver gotcha #1).
- Os processos rodam via `docker-compose.yaml` (perfil de desenvolvimento).

## Passo a passo (do zero)

```bash
# 1. Criar o .env a partir do exemplo
cp .env.example .env
# editar: SECRET_KEY_BASE (gerar com: openssl rand -hex 64)
#         SMTP_ADDRESS=mailhog   (para e-mails de teste irem ao Mailhog)

# 2. Buildar a imagem base PRIMEIRO (as demais herdam dela)
docker compose build base
docker compose build

# 3. Subir Postgres e Redis
docker compose up -d postgres redis

# 4. Preparar o banco (cria, carrega schema e roda seed)
docker compose run --rm --no-deps rails bundle exec rails db:chatwoot_prepare

# 5. Subir a stack completa
docker compose up -d
```

## Acesso

| O quê | URL | Login |
|---|---|---|
| Dashboard | http://localhost:3000 | `john@acme.inc` / `Password1!` |
| Super Admin | http://localhost:3000/super_admin | mesmo usuário |
| Mailhog (e-mails de teste) | http://localhost:8025 | — |
| Vite dev server | http://localhost:3036 | — |

> No 1º acesso a uma página o Vite compila sob demanda → pode levar dezenas de segundos.
> Depois fica rápido.

### 🔑 Credenciais de acesso (ambiente de DEV)

Criadas pelo seed (`db/seeds.rb`) — válidas **só no ambiente local de desenvolvimento**:

```
E-mail:  john@acme.inc
Senha:   Password1!
Papel:   SuperAdmin (acessa dashboard E /super_admin)
```

Observações:
- O **signup está desativado** por padrão (`ENABLE_ACCOUNT_SIGNUP=false` no `.env`),
  por isso o acesso é por este usuário do seed.
- Para **criar/editar usuários** ou trocar a senha: entre em `/super_admin`, ou use o
  console: `docker compose exec rails bundle exec rails console`.
- ⚠️ Em **produção** essas credenciais NÃO existem — lá você cria seu próprio admin.
  Nunca use `Password1!` em produção.

## Containers da stack (7)

`rails` (web :3000) · `vite` (:3036) · `sidekiq` (worker) · `postgres` (:5432) ·
`redis` (:6379) · `mailhog` (:8025/1025) · `base` (imagem base, não serve tráfego).

## Comandos do dia a dia

```bash
docker compose logs -f rails                                   # acompanhar logs
docker compose stop                                            # parar tudo
docker compose up -d                                           # subir de novo
docker compose exec rails bundle exec rails console            # console Rails
docker compose run --rm --no-deps rails bundle exec rails db:migrate   # migrar
```

---

## ⚠️ Gotchas que já resolvemos (não esquecer)

### 1. WSL2 sem limite de RAM trava o PC
Sem teto, o `Vmmem` (VM do WSL2) consome quase toda a RAM e o Windows congela —
chegando a derrubar o Docker. **Solução**: criar `C:\Users\<seu-usuario>\.wslconfig`:

```ini
[wsl2]
memory=8GB
swap=8GB
processors=4
```
Aplicar com `wsl --shutdown` e reabrir o Docker Desktop. (Em PC de 16 GB, 8 GB pro WSL
deixa 8 GB pro Windows.)

### 2. Entrypoints com quebra de linha CRLF (Windows)
Os scripts `docker/entrypoints/*.sh` (e o helper `pg_database_url.rb`) vêm com CRLF no
Windows, o que quebra o shebang no Linux:
```
exec docker/entrypoints/rails.sh: no such file or directory
```
**Solução**: converter para LF (`sed -i 's/\r$//' arquivo`) e garantir bit de execução.
Para evitar recorrência, manter um `.gitattributes` forçando LF nesses scripts.

### 3. Postgres recusa senha vazia
A imagem `pgvector/pgvector:pg16` não inicializa com `POSTGRES_PASSWORD` vazio:
```
Error: Database is uninitialized and superuser password is not specified.
```
**Solução**: no `docker-compose.yaml`, serviço `postgres`, adicionar:
```yaml
environment:
  - POSTGRES_HOST_AUTH_METHOD=trust
```
(Mantém senha vazia, coerente com o `.env` de dev. Em produção use senha real.)

### 4. Arquivos deletados da cópia de trabalho
Já aconteceu de centenas de arquivos versionados (ex.: `app/assets/config/manifest.js`,
todos os `app/javascript/dashboard/api/*.js`) sumirem do disco, quebrando o boot do Rails
(`Sprockets::Railtie::ManifestNeededError`). **Solução**: restaurar os deletados sem mexer
no que você alterou de propósito:
```bash
git ls-files -z --deleted | xargs -0 git checkout --
```

### 5. Aviso `bin/rails: shebang line ending with \r`
Mesmo problema de CRLF, mas em arquivos `.rb`. É só **aviso** — o Ruby executa mesmo
assim. Pode ignorar (ou normalizar para LF se quiser limpar).
