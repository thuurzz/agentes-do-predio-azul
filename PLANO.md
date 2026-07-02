# Laboratório "Agentes do Prédio Azul"

Plano de deploy modular com Helm. 100% compatível com EKS.

## Arquitetura

```
microk8s (single-node, ~14Gi RAM pico)
│
├── namespace: infrastructure
│   ├── postgresql       (bitnami/postgresql)
│   │   ├── keycloak_db
│   │   ├── litellm_db
│   │   └── langfuse_db
│   ├── redis            (bitnami/redis)
│   └── keycloak         (bitnami/keycloak) → :30080
│
├── namespace: litellm
│   └── litellm          (litellm-helm) → :30081
│       SSO: Keycloak (Generic OIDC)
│
└── namespace: langfuse
    ├── langfuse-web     (langfuse/langfuse) → :30082
    ├── langfuse-worker
    ├── clickhouse       (interno ao chart)
    └── minio            (interno ao chart)
        SSO: Keycloak (Provider Keycloak nativo)
```

## Estrutura do repo

```
agentes-do-predio-azul/
├── .env.example                   # Template de variáveis (commita)
├── .env                           # Variáveis reais (NÃO commita)
├── .gitignore
├── values/
│   ├── redis.yaml                 # Sem secrets
│   ├── postgresql.yaml.template
│   ├── keycloak.yaml.template
│   ├── litellm.yaml.template
│   └── langfuse.yaml.template
├── scripts/
│   ├── 01-bootstrap.sh
│   ├── 02-deploy-postgresql.sh
│   ├── 03-deploy-redis.sh
│   ├── 04-deploy-keycloak.sh
│   ├── 05-deploy-litellm.sh
│   ├── 06-deploy-langfuse.sh
│   ├── 07-configure-sso.sh
│   └── create-users.sh
├── PLANO.md
├── TESTES.md
└── README.md
```

## Diagrama de dependências

```
01-bootstrap.sh
  ├─→ 02-deploy-postgresql.sh
  ├─→ 03-deploy-redis.sh
  │    ├─→ 04-deploy-keycloak.sh    (precisa PG)
  │    │    └─→ 07-configure-sso.sh  (precisa Keycloak)
  │    ├─→ 05-deploy-litellm.sh     (precisa PG + Redis)
  │    │    └─→ 07-configure-sso.sh  (precisa Keycloak)
  │    └─→ 06-deploy-langfuse.sh    (precisa PG + Redis)
  │         └─→ 07-configure-sso.sh  (precisa Keycloak)
```

PG e Redis: paralelizáveis. Keycloak/LiteLLM/Langfuse: paralelizáveis entre si após PG+Redis.

## Ordem de execução

```bash
./scripts/01-bootstrap.sh
./scripts/02-deploy-postgresql.sh && ./scripts/03-deploy-redis.sh  # paralelo
./scripts/04-deploy-keycloak.sh    # depende PG
./scripts/05-deploy-litellm.sh     # depende PG + Redis
./scripts/06-deploy-langfuse.sh    # depende PG + Redis
./scripts/07-configure-sso.sh      # depende Keycloak
```

## Legenda de interação

| Ação | Modo |
|------|------|
| Instalar microk8s, habilitar addons | CLI (`snap`, `microk8s enable`) |
| Deploy charts (helm install/upgrade) | CLI (`helm`) |
| Verificar pods, PVCs, logs | CLI (`kubectl`) |
| Criar realm, clients, usuários Keycloak | CLI (`curl` → REST API) |
| Testar login SSO | **Browser** (localhost:30081, localhost:30082) |

## Portas

| Serviço | Local |
|---------|-------|
| Keycloak Admin | http://localhost:30080 |
| LiteLLM UI | http://localhost:30081 |
| Langfuse UI | http://localhost:30082 |
| PostgreSQL | interno 5432 |
| Redis | interno 6379 |

## Budget de memória

| Componente | Limit |
|-----------|-------|
| PostgreSQL | 1Gi |
| Redis | 512Mi |
| Keycloak | 1.5Gi |
| LiteLLM | 2Gi |
| Langfuse Web | 2Gi |
| Langfuse Worker | 2Gi |
| Clickhouse | 2Gi |
| MinIO | 512Mi |
| Zookeeper (3x) | ~1.5Gi |
| **Total pico** | **~14Gi** |

---

# Fase 1 — Bootstrap

**Modo:** CLI

- [x] 1.1 Instalar microk8s via snap (`sudo snap install microk8s --classic --channel=1.32/stable`)
- [x] 1.2 Adicionar usuário ao grupo microk8s (`sudo usermod -a -G microk8s $USER`)
- [x] 1.3 Aplicar grupo (`newgrp microk8s` ou re-login)
- [x] 1.4 Habilitar addons (`microk8s enable dns hostpath-storage helm3`)
- [x] 1.5 Aguardar cluster pronto (`microk8s status --wait-ready`)
- [x] 1.6 Criar alias (`alias kubectl='microk8s kubectl'`)
- [x] 1.7 Criar namespace `infrastructure`
- [x] 1.8 Criar namespace `litellm`
- [x] 1.9 Criar namespace `langfuse`
- [x] 1.10 Verificar: `kubectl get nodes` = Ready, `kubectl get ns` mostra 3 namespaces

---

# Fase 2 — PostgreSQL

**Modo:** CLI

- [x] 2.1 Adicionar repo bitnami (`helm repo add bitnami https://charts.bitnami.com/bitnami`)
- [x] 2.2 Criar `values/postgresql.yaml`
  - [x] `architecture: standalone`
  - [x] PVC 10Gi, `storageClass: microk8s-hostpath`
  - [x] `initdbScripts` para criar `keycloak_db`, `litellm_db`, `langfuse_db`
  - [x] resources: request 256Mi / limit 1Gi
  - [x] auth: username `litellm`, senha forte (gerar)
- [x] 2.3 Criar `scripts/02-deploy-postgresql.sh`
- [x] 2.4 Executar script
- [x] 2.5 Verificar: pod Running, PVC Bound
- [x] 2.6 Verificar: `kubectl exec` psql listando as 3 databases

---

# Fase 3 — Redis

**Modo:** CLI

- [x] 3.1 Criar `values/redis.yaml`
  - [x] `architecture: standalone`
  - [x] Sem persistência
  - [x] resources: request 128Mi / limit 512Mi
  - [x] auth: senha ou desabilitado
- [x] 3.2 Criar `scripts/03-deploy-redis.sh`
- [x] 3.3 Executar script
- [x] 3.4 Verificar: pod Running
- [x] 3.5 Verificar: `kubectl exec` redis-cli ping = PONG

---

# Fase 4 — Keycloak

**Modo:** CLI

- [x] 4.1 Criar `values/keycloak.yaml`
  - [x] `externalDatabase.host=postgresql.infrastructure`, `database=keycloak_db`
  - [x] `KC_HTTP_ENABLED=true`, `KC_HOSTNAME=localhost`
  - [x] service type `NodePort`, port `30080`
  - [x] resources: request 512Mi / limit 1.5Gi
  - [x] admin user provisionado
- [x] 4.2 Criar `scripts/04-deploy-keycloak.sh`
- [x] 4.3 Executar script
- [x] 4.4 Verificar: pod Running
- [x] 4.5 Verificar: `localhost:30080` acessível, admin login funcional

---

# Fase 5 — LiteLLM

**Modo:** CLI

- [x] 5.1 Criar `values/litellm.yaml`
  - [x] `db.useExisting=true`, endpoint apontando PG compartilhado
  - [x] `redis.enabled=false`, Redis URL via envVars
  - [x] SSO: env vars `GENERIC_CLIENT_ID`, `GENERIC_CLIENT_SECRET` (placeholder)
  - [x] SSO: endpoints Keycloak (auth, token, userinfo)
  - [x] `PROXY_BASE_URL=http://localhost:30081`
  - [x] service type `NodePort`, port `30081`
  - [x] resources: request 500Mi / limit 2Gi (ajustado: 1Gi causava OOM)
  - [x] masterkey gerada
- [x] 5.2 Criar `scripts/05-deploy-litellm.sh`
- [x] 5.3 Executar script
- [x] 5.4 Verificar: pod Running
- [x] 5.5 Verificar: `localhost:30081` acessível

---

# Fase 6 — Langfuse

**Modo:** CLI

- [x] 6.1 Adicionar repo langfuse (`helm repo add langfuse https://langfuse.github.io/langfuse-k8s`)
- [x] 6.2 Criar `values/langfuse.yaml`
  - [x] `postgresql.deploy=false`, host/creds apontando PG compartilhado
  - [x] `redis.deploy=false`, host apontando Redis compartilhado
  - [x] `clickhouse` e `s3`: deploy interno pelo chart (default)
  - [x] SSO via `additionalEnv`: `AUTH_KEYCLOAK_CLIENT_ID`, `SECRET`, `ISSUER`
  - [x] `NEXTAUTH_URL=http://localhost:30082`
  - [x] `langfuse.salt`, `langfuse.nextauth.secret` gerados
  - [x] shadow DB separado (`langfuse_shadow_db`) — exigência do Prisma
  - [x] service type `NodePort`, port `30082`
  - [x] resources: web 2Gi, worker 2Gi (ajustado: 1Gi causava OOM)
- [x] 6.3 Criar `scripts/06-deploy-langfuse.sh`
- [x] 6.4 Executar script
- [x] 6.5 Verificar: pods web + worker Running
- [x] 6.6 Verificar: `localhost:30082` acessível

---

# Fase 7 — Configurar SSO

**Modo:** CLI (curl → Keycloak REST API)

Nenhuma ação manual em browser necessária.

- [x] 7.1 Obter token admin do Keycloak (POST `/realms/master/protocol/openid-connect/token`)
- [x] 7.2 Criar realm `lab-agentes` (POST `/admin/realms`)
- [x] 7.3 Criar client `litellm` (POST `/admin/realms/lab-agentes/clients`)
  - [x] Tipo: `confidential`, OIDC
  - [x] Redirect URI: `http://localhost:30081/sso/callback`
  - [x] Extrair client secret do JSON de resposta
- [x] 7.4 Criar client `langfuse` (POST `/admin/realms/lab-agentes/clients`)
  - [x] Tipo: `confidential`, OIDC
  - [x] Redirect URI: `http://localhost:30082/api/auth/callback/keycloak`
  - [x] Extrair client secret do JSON de resposta
- [x] 7.5 Criar usuário de teste no realm `lab-agentes`
  - [x] Nome, email, senha
- [x] 7.6 Injetar client secrets e redeploy:
  - [x] `kubectl set env` LiteLLM com `GENERIC_CLIENT_SECRET`
  - [x] `kubectl set env` Langfuse com `AUTH_KEYCLOAK_CLIENT_SECRET`
  - [x] `kubectl rollout restart` ambos deployments
- [ ] 7.7 Testar login SSO no LiteLLM (`localhost:30081`) → **Browser** (usuário definido em `.env`)
- [ ] 7.8 Testar login SSO no Langfuse (`localhost:30082`) → **Browser** (usuário definido em `.env`)

---

# Verificação final

- [x] Keycloak: `http://localhost:30080` — admin login OK, realm `lab-agentes` existe
- [ ] LiteLLM: `http://localhost:30081` — login via SSO Keycloak funciona (requer browser)
- [ ] Langfuse: `http://localhost:30082` — login via SSO Keycloak funciona (requer browser)
- [x] Todos os pods: `Running` (sem CrashLoopBackOff)
- [x] Todos os PVCs: `Bound`
- [x] Memória total em uso < 15Gi