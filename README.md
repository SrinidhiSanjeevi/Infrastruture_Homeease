# HomeEase — infrastructure

Terraform for the cloud resources that run HomeEase on **Azure** (AKS) and **AWS** (ECS Fargate), plus the Azure DevOps pipelines that plan and apply it. The application is in `app_Homeease`; Kubernetes deployment configuration is in `gitops_homeease`.

```mermaid
flowchart TB
    subgraph Azure
      RG[Resource group + VNet] --> AKS[AKS cluster]
      ACR[Container registry] --> AKS
      KV[Key Vault] -->|workload identity| AKS
      MON[Log Analytics + alerts]
      BLOB[(Blob storage: service & professional images)]
    end
    subgraph AWS
      VPC[VPC + NAT with fixed IP] --> ECS[ECS Fargate cluster]
      ECR[ECR repositories] --> ECS
      SM[Secrets Manager] --> ECS
      ALB[Application Load Balancer] --> ECS
      CW[CloudWatch dashboards & alarms] --- ECS
    end
    ATLAS[(MongoDB Atlas)] --- AKS
    ATLAS --- ECS
    BLOB --- AKS
    BLOB --- ECS
```

## Azure

`environments/dev` builds the resource group, network, container registry, AKS cluster, Key Vault, Log Analytics and one workload identity per app, so pods read secrets from Key Vault without any stored credentials. `dev-identity` holds the identities the CI pipelines use.

The pipeline (`azure-pipelines.yml`):

1. **Validate** — `terraform fmt`, `validate`, TFLint, Checkov, Gitleaks and an Infracost monthly cost estimate.
2. **Plan** each environment and publish the plan. A pull request only plans.
3. **Apply dev** on `main`, behind a manual approval on the `homeease-dev` environment.

Other pipelines in `pipelines/`: a nightly **drift check** at 02:00 IST that fails when someone changes Azure by hand, and a manual **destroy** for dev that requires typing a confirmation word. Pipeline runs are serialised so two applies never fight over the state lock.

## AWS

AWS is split into two stacks that share data through `terraform_remote_state`:

- **`environments/dev`** — the foundation that survives nightly shutdowns: VPC, a NAT gateway with a fixed Elastic IP (MongoDB Atlas allows only that address), ECR repositories, empty Secrets Manager entries, and the GitHub OIDC role used by CI.
- **`environments/fargate-dev`** — the running application: ECS cluster with Service Connect, six Fargate services, the ALB, IAM, security groups, autoscaling, four CloudWatch dashboards, alarms, an SNS topic and a monthly budget.

Design choices:

- **Fargate over EC2 or EKS** — nothing to patch or scale, billing per task, and it suits six small services.
- **Service Connect** gives services short DNS names (`backend`, `payment-service`), mirroring Kubernetes service names.
- **Deployment circuit breaker** rolls back a release that never becomes healthy, and each container has its own health check.
- **Least-privilege security groups** — each service accepts traffic only from its real callers.
- **Fargate Spot** carries most capacity at lower cost, with autoscaling on CPU.
- **Secrets are never in Terraform.** Terraform creates empty containers; values are set by hand in Secrets Manager, so they stay out of the state file.

CI writes the new image tag into `terraform/aws/environments/fargate-dev/image-tags.auto.tfvars` after each successful build, so a release is `terraform apply` followed by a restart. AWS Terraform is applied by hand on purpose.
