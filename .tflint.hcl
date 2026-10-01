# tflint: lint rules beyond `terraform validate`. Run by the Validate stage.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Azure-specific checks (invalid VM sizes, SKUs, regions...) before they reach plan.
plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Accepted: modules rely on root-level provider constraints, and some
# environment variables are declared for the shared tfvars layout only.
rule "terraform_required_providers" {
  enabled = false
}

rule "terraform_unused_declarations" {
  enabled = false
}
