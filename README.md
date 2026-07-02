# Agentes do Prédio Azul

Laboratório de infraestrutura para agentes de IA. Stack completa com SSO unificado via Keycloak, LLM Gateway (LiteLLM) e Observability (Langfuse). 100% Helm, 100% compatível com EKS.

## Serviços

| Serviço | Descrição | URL | Helm Chart |
|---------|-----------|-----|------------|
| **Keycloak** | Identity Provider (SSO) | http://localhost:30080 | `bitnami/keycloak` |
| **LiteLLM** | LLM Gateway Proxy | http://localhost:30081 | `litellm-helm` |
| **Langfuse** | LLM Observability | http://localhost:30082 | `langfuse/langfuse` |
| **PostgreSQL** | Banco relacional | interno `:5432` | `bitnami/postgresql` |
| **Redis** | Cache / fila | interno `:6379` | `bitnami/redis` |

## Arquitetura

```
microk8s (single-node, ~14Gi RAM)
│
├── namespace: infrastructure
│   ├── postgresql     ── databases: keycloak_db, litellm_db, langfuse_db
│   ├── redis          ── cache + fila BullMQ
│   └── keycloak       ── SSO realm: lab-agentes
│
├── namespace: litellm
│   └── litellm        ── SSO via Keycloak (Generic OIDC)
│       └── Langfuse callback global + per-request project override
│
└── namespace: langfuse
    ├── langfuse-web     ── UI + API
    ├── langfuse-worker  ── processamento assíncrono
    ├── clickhouse       ── OLAP traces
    └── minio            ── blob storage
```

### Fluxo SSO

```
Browser ──→ LiteLLM (localhost:30081)
  └─→ Keycloak (192.168.1.10:30080) ──→ login ──→ redirect callback
        └─→ LiteLLM troca code por token (server→server, mesmo host)
              └─→ userinfo valida token (mesmo issuer)
```

### Fluxo Tracing

```
Cliente ──→ POST /chat/completions { metadata: { langfuse_public_key: "pk-...", langfuse_secret_key: "sk-..." } }
  └─→ LiteLLM ──→ LLM Provider (OpenAI, etc)
        └─→ success_callback: langfuse
              └─→ Langfuse (projeto definido pelas chaves no metadata)
```

## Pré-requisitos

- Ubuntu 22.04+ com snap
- 32GB RAM (uso ~14Gi no pico)
- Acesso sudo (instalação inicial do microk8s)

## Quick Start

```bash
# 0. Gerar secrets
./scripts/generate-secrets.sh

# 1. Bootstrap do cluster
./scripts/01-bootstrap.sh

# 2. Infra base
./scripts/02-deploy-postgresql.sh
./scripts/03-deploy-redis.sh

# 3. Serviços
./scripts/04-deploy-keycloak.sh
./scripts/05-deploy-litellm.sh
./scripts/06-deploy-langfuse.sh

# 4. Configurar SSO (preenche client secrets no .env)
./scripts/07-configure-sso.sh

# 5. Criar API key no Langfuse UI e preencher no .env:
#    LANGFUSE_PUBLIC_KEY=<sua chave>
#    LANGFUSE_SECRET_KEY=<sua chave>
```

> **Importante:** Os scripts carregam variáveis do `.env` e geram `values/*.yaml` dinamicamente via `envsubst`. Nenhum secret fica hardcoded nos YAMLs.

## Acessos

### Admin

| Serviço | URL | Usuário | Senha |
|---------|-----|---------|-------|
| Keycloak | http://localhost:30080 | `admin` | `<KEYCLOAK_ADMIN_PASSWORD>` |
| LiteLLM | http://localhost:30081 | master key | `<LITELLM_MASTER_KEY>` |

### Usuário SSO (teste)

| URL | Usuário | Senha |
|-----|---------|-------|
| LiteLLM → Sign in with SSO | `<SSO_TEST_USER>` | `<SSO_TEST_PASSWORD>` |
| Langfuse → Sign in with Keycloak | `<SSO_TEST_USER>` | `<SSO_TEST_PASSWORD>` |
| Demais usuários | `<usuario1..usuario5>` | `<definido no create-users.sh>` |

## Estrutura

```
├── .env.example                   # Template de variáveis (commita)
├── .env                           # Variáveis reais (NÃO commita)
├── .gitignore
├── PLANO.md                       # Plano detalhado com fases e checklists
├── TESTES.md                      # Guia de testes e fluxo integrado
├── README.md                      # Este arquivo
├── scripts/
│   ├── 01-bootstrap.sh            # microk8s + namespaces
│   ├── 02-deploy-postgresql.sh    # bitnami/postgresql
│   ├── 03-deploy-redis.sh         # bitnami/redis
│   ├── 04-deploy-keycloak.sh      # bitnami/keycloak
│   ├── 05-deploy-litellm.sh       # litellm-helm
│   ├── 06-deploy-langfuse.sh      # langfuse/langfuse
│   ├── 07-configure-sso.sh        # Keycloak realm + clients + usuário
│   ├── create-users.sh            # Criar usuários em lote
│   └── generate-secrets.sh        # Gerar .env com valores aleatórios
└── values/
    ├── redis.yaml                 # Sem secrets, commita direto
    ├── postgresql.yaml.template
    ├── keycloak.yaml.template
    ├── litellm.yaml.template
    └── langfuse.yaml.template
```

## Aprendizados p/ produção (EKS)

### 1. Keycloak: hostname único para SSO funcionar

O issuer do Keycloak precisa ser acessível tanto do browser quanto dos pods. Solução: IP do node (lab) ou domínio real (EKS).

```yaml
# keycloak.yaml
extraEnvVars:
  - name: KC_HOSTNAME_URL           # URL completa com protocolo
    value: "http://192.168.1.10:30080"   # lab: IP do node
    # value: "https://sso.empresa.com"   # EKS: domínio real
  - name: KC_HOSTNAME_STRICT
    value: "false"                  # aceita requests de qualquer hostname
```

No LiteLLM, TODOS os endpoints SSO (`GENERIC_*_ENDPOINT`) apontam pra mesma URL.

### 2. LiteLLM SSO: callback é endpoint do LiteLLM, auth é do Keycloak

- `PROXY_BASE_URL` = URL do LiteLLM (onde o browser volta) — pode ser `localhost:30081`
- `GENERIC_AUTHORIZATION_ENDPOINT` = URL externa do Keycloak — mesma do `KC_HOSTNAME_URL`
- `GENERIC_TOKEN_ENDPOINT` / `GENERIC_USERINFO_ENDPOINT` = mesma URL (server→server)

### 3. Langfuse tracing: chaves globais inicializam, metadata roteia por projeto

```yaml
# litellm.yaml
proxy_config:
  litellm_settings:
    success_callback: ["langfuse"]
    failure_callback: ["langfuse"]
  general_settings:
    allow_client_side_credentials: true   # permite override por requisição

envVars:
  LANGFUSE_HOST: "http://langfuse-web.langfuse.svc.cluster.local:3000"
  LANGFUSE_PUBLIC_KEY: "pk-lf-..."        # chave de projeto default (obrigatória)
  LANGFUSE_SECRET_KEY: "sk-lf-..."
```

Chaves globais inicializam o cliente. `metadata` na requisição sobrescreve qual projeto recebe o trace:

```bash
curl ... -d '{"model": "gpt-4.1", "messages": [...],
  "metadata": {
    "langfuse_public_key": "pk-lf-PROJETO-X",
    "langfuse_secret_key": "sk-lf-PROJETO-X"
  }}'
```

### 4. Email: domínio `.local` rejeitado

Pydantic rejeita TLDs reservados. Usar `@predioazul.com` ou outro TLD válido.

### 5. Helm upgrade reseta NodePort

Helm redefine service pra ClusterIP a cada upgrade. Patch separado:

```bash
kubectl patch svc litellm -n litellm -p '{"spec":{"ports":[{"name":"http","port":4000,"targetPort":"http","nodePort":30081}]}}'
```

### 6. Bitnami paywall (Agosto 2025)

Imagens gratuitas movidas pra `bitnamilegacy`. Charts que usam imagens bitnami precisam do override:

```yaml
# keycloak.yaml
image:
  registry: docker.io
  repository: bitnamilegacy/keycloak
```

### 7. LiteLLM + Langfuse: OOM com < 2Gi

Ambos precisam de pelo menos 2Gi de limite de memória. Abaixo disso morrem com OOMKilled.

## Destruir

```bash
kubectl delete namespace infrastructure litellm langfuse
microk8s reset
```

## Documentação relacionada

- [PLANO.md](./PLANO.md) — plano completo com fases, checklists e dependências
- [TESTES.md](./TESTES.md) — passo a passo para testar cada serviço e fluxo integrado
