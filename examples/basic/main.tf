terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# A public Standard load balancer that actually serves traffic: an HTTP health
# probe, a load balancing rule bound to it, and an explicit outbound rule so the
# backend instances keep internet egress (default outbound access was retired on
# 2025-09-30).
module "load_balancer" {
  source = "../.."

  name                = "example-lb"
  resource_group_name = "example-rg"
  location            = "eastus"
  sku                 = "Standard"

  frontend_ip_configurations = [
    {
      name                 = "public"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/publicIPAddresses/example-pip"
    }
  ]

  backend_pool_names = ["web-pool"]

  health_probes = [
    {
      name         = "http"
      protocol     = "Http"
      port         = 80
      request_path = "/healthz"
    }
  ]

  load_balancing_rules = [
    {
      name                           = "http"
      frontend_ip_configuration_name = "public"
      backend_pool_name              = "web-pool"
      probe_name                     = "http"
      protocol                       = "Tcp"
      frontend_port                  = 80
      backend_port                   = 80
    }
  ]

  outbound_rules = [
    {
      name                            = "egress"
      backend_pool_name               = "web-pool"
      frontend_ip_configuration_names = ["public"]
      protocol                        = "All"
      allocated_outbound_ports        = 1024
    }
  ]

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "load_balancer_id" {
  value = module.load_balancer.id
}

output "load_balancing_rule_ids" {
  value = module.load_balancer.load_balancing_rule_ids
}

output "outbound_rule_ids" {
  value = module.load_balancer.outbound_rule_ids
}
