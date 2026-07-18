terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

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

  tags = {
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

output "load_balancer_id" {
  value = module.load_balancer.id
}
