# ============================================================
# Secrets Manager CONTAINERS only — same rule as
# terraform/azure/modules/keyvault/SECRETS.md: Terraform manages the
# secret's existence and who can read it, never its value. No
# aws_secretsmanager_secret_version resource exists anywhere in this
# module, on purpose — that resource type is how a real value ends up
# in Terraform state in plaintext. See SECRETS.md in this directory
# for how values actually get set.
# ============================================================

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(var.secret_names)

  name = "${var.name_prefix}/${each.value}"

  # 0 = delete immediately instead of the 7-30 day recovery window.
  # Convenient for a dev secret you might recreate under the same name
  # while iterating; set higher (or leave the AWS default) once a
  # secret here is real and losing it would hurt.
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    secret = each.value
  })
}
