# ============================================================
# Updated by app_Homeease's aws-ci.yml after a successful build + scan
# + sign + push to ECR — one commit per run, same mechanism
# azure-pipelines.yml's Promote stage already uses against
# gitops_homeease's values-azure-dev.yaml. Do not hand-edit while CI
# owns this file; a manual edit is fine before the first real image
# exists (these placeholders won't resolve to anything in ECR yet).
# ============================================================

image_tags = {
  backend         = "metrics-1"
  admin_backend   = "89617ff8897b"
  frontend        = "89617ff8897b"
  admin_frontend  = "89617ff8897b"
  payment_service = "89617ff8897b"
}
