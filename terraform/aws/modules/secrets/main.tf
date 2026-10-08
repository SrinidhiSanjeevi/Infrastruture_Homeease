# Secrets Manager CONTAINERS only

resource "aws_secretsmanager_secret" "this" {
  for_each = toset(var.secret_names)

  name = "${var.name_prefix}/${each.value}"

  # 0 = delete immediately instead of the 7-30 day recovery window.
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, {
    secret = each.value
  })
}
