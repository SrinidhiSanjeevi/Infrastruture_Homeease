# Self-hosted SonarQube — one-time setup

Both CI pipelines (`app_Homeease/azure-pipelines.yml` and
`app_Homeease/.github/workflows/aws-ci.yml`) run a Sonar quality-gate
step per service. This is the server they call.

## 1. Stand it up

```bash
cp .env.example .env    # then edit SONAR_DB_PASSWORD
sudo sysctl -w vm.max_map_count=262144   # required once per host, Elasticsearch will not start otherwise
docker compose up -d
```

Wait for `docker compose logs -f sonarqube` to show `SonarQube is
operational`, then open `http://127.0.0.1:9000` (via SSH tunnel, or
through the reverse proxy once one is in front of it) and change the
default `admin` / `admin` password immediately.

## 2. Put TLS in front of it

CI providers call this over the public internet. Never point
`SONAR_HOST_URL` at plain HTTP. Put Caddy or nginx + Let's Encrypt in
front, terminating TLS, before doing anything else.

## 3. Create one project per service, generate one token

In SonarQube: **Projects → Create Project → Manually**, project key
matching what the pipelines already send:

| Project key | Service |
|---|---|
| `homeease-backend` | backend |
| `homeease-admin-backend` | admin-backend |
| `homeease-payment-service` | payment-service |
| `homeease-frontend` | frontend |

Then **My Account → Security → Generate Token** — one token is
enough for all four projects if it belongs to a CI-only account with
the `Execute Analysis` permission, rather than a personal admin
account.

## 4. Wire it into each CI provider

**Azure DevOps** (`app_Homeease` pipeline):
1. Install the **SonarQube** Marketplace extension in the organisation.
2. Project settings → Service connections → New → SonarQube, name it
   `sonarqube-service-connection` (the exact name `azure-pipelines.yml`
   expects) — server URL + the token from step 3.
3. Pipelines → Library → Variable group `homeease-ci` (linked to Key
   Vault per `ANALYSIS.md` §5) → add `SONAR_TOKEN`, `SONAR_HOST_URL`.

**GitHub Actions** (`app_Homeease` `aws-ci.yml`):
- Settings → Secrets and variables → Actions → **Secrets** →
  `SONAR_TOKEN`, `SONAR_HOST_URL`. (Secrets, not variables — Sonar has
  no OIDC federation, so this is a real long-lived credential; rotate
  it periodically and scope the token to analysis-only.)

## Why Postgres, why pinned, why 127.0.0.1

- SonarQube's default H2 database is explicitly unsupported beyond a
  five-minute evaluation and does not survive a container recreate —
  Postgres is not optional hardening here, it is the minimum for the
  data to persist past `docker compose down`.
- The image tag is pinned to a specific build
  (`26.9.0.129388-community` at time of writing — check
  `hub.docker.com/_/sonarqube/tags` for the current one before
  bumping it) rather than the floating `community` tag, for the same
  "never a moving reference" reason the CI pipelines pin trivy,
  gitleaks, hadolint, syft and cosign by exact version.
- The container binds `127.0.0.1:9000` only. Whatever reverse proxy
  you put in front of it is the only thing that should ever see port
  9000 directly.
