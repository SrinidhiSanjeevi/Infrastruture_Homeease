# ============================================================
# Updated by app_Homeease's aws-ci.yml after a successful build + scan
# + sign + push to ECR — one commit per run, same mechanism
# azure-pipelines.yml's Promote stage already uses against
# gitops_homeease's values-azure-dev.yaml. Do not hand-edit while CI
# owns this file; a manual edit is fine before the first real image
# exists (these placeholders won't resolve to anything in ECR yet).
# ============================================================

image_tags = {
  backend              = "c3c0aabad723"
  admin_backend        = "c3c0aabad723"
  frontend             = "c3c0aabad723"
  admin_frontend       = "c3c0aabad723"
  payment_service      = "301b844fbb44"
  notification_service = "a2822dbb135f"
}
