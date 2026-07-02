# Guia de Testes — Laboratório "Agentes do Prédio Azul"

## Acessos

| Serviço | URL | Login | Senha |
|---------|-----|-------|-------|
| Keycloak Admin | http://localhost:30080 | `admin` | `<KEYCLOAK_ADMIN_PASSWORD>` |
| LiteLLM UI | http://localhost:30081 | `tester` (via SSO) | `<SSO_TEST_PASSWORD>` |
| Langfuse UI | http://localhost:30082 | `tester` (via SSO) | `<SSO_TEST_PASSWORD>` |
| PostgreSQL | interno `postgresql.infrastructure:5432` | `litellm` | `<PG_PASSWORD>` |
| Redis | interno `redis-master.infrastructure:6379` | — | sem senha |

> **Usuários SSO:** `tester / <SSO_TEST_PASSWORD>` + 5 extras (`usuario1..usuario5 / <definir>`). Criar mais: `./scripts/create-users.sh`

---

## 1. Keycloak — Identity Provider

### 1.1 Acessar console admin
```
http://localhost:30080
```
Login: `admin` / `<KEYCLOAK_ADMIN_PASSWORD>`

### 1.2 Verificar realm
- No menu superior esquerdo, selecionar realm `lab-agentes`
- Ir em **Users** → ver usuários `tester`, `usuario1..usuario5`

### 1.3 Verificar clients OIDC
- Ir em **Clients**
- Confirmar que `litellm` e `langfuse` existem
- Clicar em cada um, aba **Credentials** → confirmar Client Secret preenchido

### 1.4 Testar OIDC discovery endpoint
```bash
curl http://192.168.1.10:30080/realms/lab-agentes/.well-known/openid-configuration | python3 -m json.tool | head -20
```
Deve retornar issuer `http://192.168.1.10:30080/realms/lab-agentes`.

### 1.5 Criar mais usuários
```bash
# 5 usuários padrão (usuario1..usuario5 / <definir>)
./scripts/create-users.sh

# Customizado
USERS="alice bob" ./scripts/create-users.sh
```

---

## 2. LiteLLM — LLM Gateway

### 2.1 Acessar UI
```
http://localhost:30081/ui
```

### 2.2 Login via SSO (Keycloak)
1. Na tela de login, clicar **"Sign in with SSO"**
2. Redirecionado para Keycloak → login: `tester` / `<SSO_TEST_PASSWORD>`
3. Redirecionado de volta ao LiteLLM logado

> **Fallback:** Se SSO falhar, acessar `http://localhost:30081/fallback/login`

### 2.3 Verificar health
```bash
curl http://localhost:30081/health/readiness
# {"status":"healthy","db":"connected"}
```

### 2.4 Testar API (com master key)
```bash
curl http://localhost:30081/v1/models \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>"
```
Deve listar modelos (ao menos `gpt-3.5-turbo`).

---

## 3. Langfuse — Observability

### 3.1 Acessar UI
```
http://localhost:30082
```

### 3.2 Login via SSO (Keycloak)
1. Na tela de login, clicar **"Sign in with Keycloak"**
2. Redirecionado para Keycloak → login: `tester` / `<SSO_TEST_PASSWORD>`
3. Redirecionado de volta ao Langfuse logado
4. Criar organização e projeto (primeiro acesso)

### 3.3 Verificar health
```bash
curl http://localhost:30082/api/public/health
```

### 3.4 Criar API keys para tracing

> **Cada projeto/org no Langfuse tem seu próprio par de API keys.**
> Isso isola traces por projeto — fundamental para multi-tenancy.

1. No Langfuse UI → **Settings** → **API Keys**
2. Criar nova chave
3. Anotar `LANGFUSE_PUBLIC_KEY` (`pk-lf-...`) e `LANGFUSE_SECRET_KEY` (`sk-lf-...`)
4. Repetir para cada projeto que precisar de tracing

---

## 4. Fluxo integrado — LiteLLM + Langfuse + Keycloak

Objetivo: requisição LLM via LiteLLM com tracing no Langfuse, autenticado via Keycloak.
**Traces isolados por projeto Langfuse via `metadata` na chamada.**

### 4.1 Pré-requisitos
- SSO funcional no LiteLLM e Langfuse
- API keys do Langfuse (passo 3.4 — um par por projeto)
- Master key do LiteLLM: `<LITELLM_MASTER_KEY>`

### 4.2 Requisição com tracing por projeto

Credenciais do Langfuse no campo `metadata` do body da requisição.
Cada projeto/org usa suas próprias chaves → trace vai pro projeto correto.

```bash
curl -X POST http://localhost:30081/chat/completions \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1",
    "messages": [{"role": "user", "content": "Diga ola em uma frase curta"}],
    "metadata": {
      "langfuse_public_key": "pk-lf-SEU-PROJETO",
      "langfuse_secret_key": "sk-lf-SEU-PROJETO"
    }
  }'
```

> **Como funciona:**
> - As chaves globais (`LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY`) inicializam o cliente Langfuse no LiteLLM (obrigatório)
> - O `metadata` por requisição sobrescreve qual projeto recebe o trace
> - Sem `metadata` → trace cai no projeto das chaves globais
> - `allow_client_side_credentials: true` (já configurado) libera o override por requisição

### 4.3 Verificar trace no Langfuse
1. Abrir `http://localhost:30082`
2. Navegar até o projeto → **Traces**
3. A requisição aparece com detalhes (latência, tokens, custo)

---

## 5. Comandos úteis

Substituir `kubectl` por `microk8s kubectl` no ambiente local.

### Status geral
```bash
kubectl get pods -A | grep -E 'infrastructure|litellm|langfuse'
```

### Logs por serviço
```bash
kubectl logs -n infrastructure statefulset/keycloak
kubectl logs -n infrastructure statefulset/postgresql
kubectl logs -n infrastructure statefulset/redis-master
kubectl logs -n litellm deploy/litellm
kubectl logs -n langfuse deploy/langfuse-web
kubectl logs -n langfuse deploy/langfuse-worker
```

### Reiniciar serviço
```bash
kubectl rollout restart deploy/litellm -n litellm
kubectl rollout restart deploy/langfuse-web -n langfuse
kubectl rollout restart deploy/langfuse-worker -n langfuse
kubectl rollout restart statefulset/keycloak -n infrastructure
```

### Acessar PostgreSQL
```bash
kubectl exec -n infrastructure postgresql-0 -- env "PGPASSWORD=<PG_PASSWORD>" psql -U litellm -d litellm
```

### Acessar Redis
```bash
kubectl exec -n infrastructure redis-master-0 -- redis-cli
# ping / keys * / dbsize
```

---

## 6. Troubleshooting

| Problema | Causa provável | Solução |
|----------|---------------|---------|
| Keycloak não abre | Pod não ready | `kubectl get pods -n infrastructure` |
| LiteLLM SSO não funciona | Client secret errado ou issuer inconsistente | Rodar `07-configure-sso.sh` novamente |
| LiteLLM OOMKilled | Memória insuficiente | Aumentar `resources.limits.memory` (mín 2Gi) |
| Langfuse "shadow database" | DB shadow = DB principal | Shadow DB já criado como `langfuse_shadow_db` |
| Langfuse Clickhouse não conecta | Zookeeper inicializando | Aguardar 2-3 min, Clickhouse reconecta |
| SSO: "not a valid email address" | Domínio `.local` rejeitado pelo pydantic | Email com TLD válido (`@predioazul.com`) |
| SSO: "Invalid token issuer" | Hostname Keycloak inconsistente | `KC_HOSTNAME_URL` = IP do node ou domínio real, mesma URL em todos endpoints |
| SSO: erro no Langfuse após login | `NEXTAUTH_URL` ou issuer errado | `NEXTAUTH_URL` = porta NodePort; `AUTH_KEYCLOAK_ISSUER` = URL externa |
| Tracing não aparece no Langfuse | Cliente Langfuse não inicializado | Conferir `LANGFUSE_PUBLIC_KEY`/`SECRET_KEY` no pod |
| "langfuse_public_key is not allowed" | Bloqueio de segurança | `general_settings.allow_client_side_credentials: true` no config |
| Helm upgrade reseta NodePort | Service volta pra ClusterIP | `kubectl patch svc` após upgrade |
