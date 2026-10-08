# HomeEase — Production Readiness Review

- **Date:** 2026-10-07
- **Scope:** `app_Homeease`, `Infrastructure_Homeease`, `gitops_homeease`
- **Platforms:** Azure (AKS + Argo CD), AWS (ECS Fargate), MongoDB Atlas
- **Note:** written before the move to EKS ([ADR-0002](adr/0002-eks-with-gitops-on-aws.md)); the AWS findings describe the Fargate stack, which is now legacy
- **Reviewer:** engineering review against a Google-SRE-style PRR checklist

A Production Readiness Review asks one question per dimension: *what happens
when this breaks, grows, or is handed to someone else?* Items marked
**Accepted** are deliberate trade-offs under free-tier and credit constraints,
not oversights.

---

## 1. Verified strengths

These were audited against the code, not assumed.

| Area | Evidence |
|---|---|
| **Double-booking prevention** | `SlotReservation` carries a unique compound index on `{professional, date, timeSlot}`. The database refuses a conflicting slot regardless of how many replicas race. |
| **Connection pool sizing** | `maxPoolSize: 10` in `config/db.js`. Six services × 2 tasks = ~120 connections, comfortably inside Atlas shared-tier limits. Mongoose's default of 100 would have risked exhaustion. |
| **Scheduler leader election** | `services/scheduler.js` takes a lease in a `locks` collection and handles `E11000` to stand down. Background jobs run once across N replicas. |
| **Query indexing** | Purpose-built indexes for user history, professional job queues, reassignment sweeps and a `2dsphere` geo index. |
| **Container security** | Non-root `USER`, `HEALTHCHECK`, `allowPrivilegeEscalation: false`, `capabilities: drop ALL`, read-only root filesystem, private subnets only. |
| **Supply chain** | gitleaks on full history, hadolint, Trivy, SonarQube quality gate, npm audit — 0 production vulnerabilities at review time. |
| **Deployment safety** | ECS circuit breaker with automatic rollback; Argo CD `selfHeal`, `prune`, retry limit 5; zero-downtime rolling config. |
| **Observability** | 14 Prometheus alert rules, Grafana dashboards (business, RED, payment, logs), Loki aggregation, DORA metrics exporter, CloudWatch dashboards and alarms. |

---

## 2. Failure handling

### Covered

- **Instance failure** — ECS replaces failed tasks; Kubernetes restarts failed pods via liveness probes.
- **Bad deploy** — ECS deployment circuit breaker rolls back automatically; Argo CD self-heals drift.
- **Partial outage** — HPA and ECS target-tracking autoscaling absorb load shifts.
- **Duplicate background work** — scheduler lease (above).
- **Database blip** — mongoose reconnect handlers with logging; 30s server-selection timeout.

### Gaps

| Gap | Risk | Recommendation |
|---|---|---|
| **No cross-service transaction boundary** | A booking write, a payment capture and a notification span three services with no `startSession`/`withTransaction`, no idempotency keys and no outbox. A payment can succeed while the booking write fails — money taken, no booking. | Add an **idempotency key** on the payment call (client-generated, stored, replay-safe), and an **outbox collection** written in the same operation as the booking, drained by the notification path. This is the single most valuable engineering addition to the project. |
| **Atlas backup posture undocumented** | Atlas M0 (free tier) has **no automated backups**. If the project runs on M0, booking data is unrecoverable after a bad migration or accidental drop. | Confirm the cluster tier. If M0, schedule a `mongodump` to object storage from CI on a cron, and record the restore procedure. |
| **No documented RTO/RPO** | "How long to recover, how much data lost" has no stated answer. | State targets even if modest, e.g. RTO 4h / RPO 24h for a dev-tier project, and test a restore once. |
| **Single NAT gateway** | One AZ failure removes egress for all private subnets. | **Accepted, and partly deliberate.** The single NAT carries a fixed Elastic IP, which is what makes the MongoDB Atlas IP allowlist possible — Atlas admits that one address instead of `0.0.0.0/0`. A second NAT means a second egress IP to allowlist, plus ~$32/month. The availability trade was taken knowingly in exchange for a tighter database perimeter. |
| **No DR drill or chaos testing** | Recovery is theoretical until exercised. | Kill a task and a pod during a demo; it is a 60-second proof that self-healing works. |

---

## 3. Scalability

### Covered

- Horizontal autoscaling on both platforms (HPA on AKS 1-3, App Auto Scaling on ECS, AKS node pool 1-3).
- CloudFront CDN in front of static assets.
- Connection pooling bounded per task, so scaling out does not exhaust the database.
- Rate limiting per route class (auth, general, payment, emergency).
- Indexed query paths for the hot collections.

### Gaps

| Gap | Recommendation |
|---|---|
| **No load test** | Autoscaling thresholds (70% CPU) are untested assumptions. A 20-minute k6 or Artillery run against the booking API would turn them into measured numbers — and gives a real figure to quote. |
| **Database is the scaling ceiling** | Shared-tier Atlas caps throughput regardless of how many tasks run. Application tier scales; data tier does not. Name this explicitly — knowing your bottleneck is a senior signal. |
| **No caching layer** | Service listings and professional search hit Mongo on every request. Redis or in-process TTL caching would cut read load cheaply. |
| **No capacity plan** | No stated "this handles N bookings/hour". Derive it from the load test. |

---

## 4. Automation

### Covered

- CI/CD on both clouds: Azure DevOps (7 stages) and GitHub Actions.
- Per-service change detection — only changed services rebuild.
- Automated image tag promotion into the GitOps repo.
- GitOps continuous reconciliation via Argo CD.
- DORA metrics collected automatically from CI/CD history.
- OIDC federation — no long-lived cloud credentials anywhere.
- Infracost and Checkov gates on infrastructure changes.

### Gaps

| Gap | Recommendation |
|---|---|
| **No automated dependency updates** | Enable Dependabot or Renovate. Free on GitHub, and it demonstrates sustained supply-chain hygiene rather than a one-time scan. |
| **Terraform drift detection not running** | `pipelines/terraform-drift.yml` existed but was never registered as a pipeline. Either register it or state that plan-before-apply is the control. |
| **No scheduled security scan** | Scans run only on change. A weekly scheduled Trivy/gitleaks run catches newly disclosed CVEs in unchanged images. |
| **No automated backup verification** | A backup that has never been restored is a hypothesis. |

---

## 5. Multi-person operation

This is where the project is furthest from production practice, because it was
built by one engineer. Every item below is cheap and fast to add.

| Gap | Why it matters with N engineers | Priority |
|---|---|---|
| **GitOps repo branch protection** | **Highest risk item in the review.** `gitops_homeease` is the deployment control plane: Argo CD auto-syncs it with `prune: true` and `selfHeal: true`. An unreviewed push to `main` reaches the live cluster within minutes, and `prune` can delete resources. The app repo is protected; this one must be too. | **Critical** |
| **Infra repo branch protection** | An unreviewed Terraform merge triggers plan and an approval-gated apply. Weaker blast radius than GitOps, but still production infrastructure. | High |
| **No CODEOWNERS** | Nothing routes an infra or chart change to the person who owns it. Reviews land on whoever notices. | High |
| **No versioned database migrations** | Migration scripts exist under `backend/scripts/migrations/` but are ad-hoc, with no version tracking or applied-state record. Two engineers changing the same collection produce silent drift, and nobody can tell which migrations ran against which environment. Adopt `migrate-mongo` or equivalent. | High |
| **No PR template** | Checklists (tests added, migration needed, rollback plan) are how teams make review consistent. | Medium |
| **No CONTRIBUTING / onboarding doc** | A new engineer cannot discover the three-repo relationship, the promotion flow, or local setup without being told. | Medium |
| **Secrets held by one person** | `GITOPS_PAT`, `GITOPS_PROD_PAT` and Atlas credentials have no documented owner, rotation schedule or break-glass procedure. | Medium |
| **No on-call or alert routing** | 14 alert rules fire into SNS and a webhook. With a team, alerts need an owner and an escalation path. | Low (project scale) |

---

## 6. Operating like industry, under free-tier constraints

The constraint is not a limitation to apologise for — cost-aware architecture
is a core competency, and these are the same levers real teams pull.

| Technique | Status here |
|---|---|
| **Spot/preemptible compute for non-critical workloads** | In use — Fargate Spot with an on-demand base |
| **Scale-to-zero or scheduled shutdown for non-prod** | **Architected for, not yet automated.** The AWS stack is deliberately split so `environments/dev` (VPC, NAT, ECR, secrets, OIDC) survives while `environments/fargate-dev` (the running app) can be destroyed nightly. The split is the hard part and it is done; what is missing is the schedule that drives it. Automating it removes roughly two-thirds of compute hours — the single largest remaining saving. |
| **One real environment, others plan-only** | In use — staging and prod are demo-only, deliberately |
| **Free CI tiers** | In use — GitHub Actions and Azure DevOps free minutes, with caching and change detection to stay inside them |
| **Free observability tiers** | Self-hosted Prometheus/Grafana/Loki on the existing cluster rather than paid SaaS |
| **Budget alarms before overspend** | In use — AWS Budgets, Infracost on PRs |
| **Right-sizing over over-provisioning** | In use — 256 CPU / 512 MiB tasks, pool size 10 |
| **Free-tier managed data** | Atlas M0 — with the backup caveat in §2 |

---

## 7. Recommended order of work

1. **Protect `main` on the GitOps repo** — minutes to do, highest risk reduction.
2. **Confirm the Atlas tier and backup story**; add a scheduled dump if M0.
3. **Add idempotency keys to the payment path** — the real correctness gap.
4. **Add CODEOWNERS and a PR template** to all three repos.
5. **Adopt versioned migrations** before a second engineer touches the schema.
6. Apply CloudTrail + GuardDuty; add WAF in count mode.
7. Run one load test; record the numbers.
8. Enable Dependabot; register or retire drift detection.
