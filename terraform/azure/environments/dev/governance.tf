# Azure Policy: every taggable resource in the environment's resource group
# must carry the standard tags (cost reporting, ownership, audit).
# Built-in definition "Require a tag on resources".

locals {
  required_tags = ["project", "environment", "owner"]
}

resource "azurerm_resource_group_policy_assignment" "require_tag" {
  for_each = var.enable_tag_policy ? toset(local.required_tags) : toset([])

  name                 = "require-tag-${each.key}"
  display_name         = "Require tag '${each.key}' on resources"
  resource_group_id    = module.resource_group.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"

  parameters = jsonencode({
    tagName = { value = each.key }
  })
}
