# Requires Terraform >= 1.7 / OpenTofu >= 1.7 for `mock_provider`. This is a
# test-only requirement: the module itself still supports >= 1.5.

mock_provider "azurerm" {
  # The azurerm provider parses resource IDs even when mocked, so the generated
  # IDs have to be well formed.
  mock_resource "azurerm_lb" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/loadBalancers/example-lb"
    }
  }

  mock_resource "azurerm_lb_backend_address_pool" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/loadBalancers/example-lb/backendAddressPools/example-pool"
    }
  }

  mock_resource "azurerm_lb_probe" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/loadBalancers/example-lb/probes/example-probe"
    }
  }

  mock_resource "azurerm_lb_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/loadBalancers/example-lb/loadBalancingRules/example-rule"
    }
  }

  mock_resource "azurerm_lb_outbound_rule" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/loadBalancers/example-lb/outboundRules/example-outbound-rule"
    }
  }
}

variables {
  name                = "example-lb"
  resource_group_name = "example-rg"
  location            = "eastus"

  frontend_ip_configurations = [
    {
      name                 = "public"
      public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/publicIPAddresses/example-pip"
    }
  ]
}

run "sku_defaults_to_standard" {
  assert {
    condition     = azurerm_lb.this.sku == "Standard"
    error_message = "Default SKU must be Standard. Basic was retired on 2025-09-30 and has no zone redundancy."
  }
}

run "rejects_unknown_sku" {
  variables {
    sku = "premium"
  }

  command = plan

  expect_failures = [var.sku]
}

run "rejects_frontend_with_neither_public_ip_nor_subnet" {
  variables {
    frontend_ip_configurations = [
      {
        name = "orphan"
      }
    ]
  }

  command = plan

  expect_failures = [var.frontend_ip_configurations]
}

run "rejects_frontend_with_both_public_ip_and_subnet" {
  variables {
    frontend_ip_configurations = [
      {
        name                 = "both"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/publicIPAddresses/example-pip"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/example-subnet"
      }
    ]
  }

  command = plan

  expect_failures = [var.frontend_ip_configurations]
}

run "accepts_internal_frontend" {
  variables {
    frontend_ip_configurations = [
      {
        name                          = "internal"
        subnet_id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/example-subnet"
        private_ip_address            = "10.0.1.10"
        private_ip_address_allocation = "Static"
      }
    ]
  }

  assert {
    condition     = one(azurerm_lb.this.frontend_ip_configuration).private_ip_address_allocation == "Static"
    error_message = "A pinned private IP must be allocated statically."
  }
}

run "rejects_pinned_private_ip_with_dynamic_allocation" {
  variables {
    frontend_ip_configurations = [
      {
        name               = "internal"
        subnet_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/example-subnet"
        private_ip_address = "10.0.1.10"
      }
    ]
  }

  command = plan

  expect_failures = [var.frontend_ip_configurations]
}
