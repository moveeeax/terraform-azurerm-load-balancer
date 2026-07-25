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
      frontend_port                  = 80
      backend_port                   = 80
    }
  ]
}

run "rule_is_bound_to_its_probe_and_pool" {
  assert {
    condition     = azurerm_lb_rule.this["http"].probe_id == azurerm_lb_probe.this["http"].id
    error_message = "Load balancing rule must reference its health probe; Azure rejects a rule without one."
  }

  assert {
    condition     = azurerm_lb_rule.this["http"].backend_address_pool_ids == tolist([azurerm_lb_backend_address_pool.this["web-pool"].id])
    error_message = "Load balancing rule must reference the named backend pool."
  }
}

# With no outbound rule, the load balancing rule itself must keep providing
# implicit outbound SNAT, otherwise the backend pool has no egress at all.
run "snat_stays_enabled_without_an_outbound_rule" {
  assert {
    condition     = azurerm_lb_rule.this["http"].disable_outbound_snat == false
    error_message = "Without an outbound rule the load balancing rule must keep implicit outbound SNAT enabled."
  }
}

# Once an outbound rule owns SNAT for the pool, the load balancing rule must
# stand down so the two do not fight over SNAT port allocation.
run "snat_is_handed_over_to_the_outbound_rule" {
  variables {
    outbound_rules = [
      {
        name                            = "egress"
        backend_pool_name               = "web-pool"
        frontend_ip_configuration_names = ["public"]
      }
    ]
  }

  assert {
    condition     = azurerm_lb_rule.this["http"].disable_outbound_snat == true
    error_message = "When an outbound rule covers the backend pool, the load balancing rule must disable its own outbound SNAT."
  }

  assert {
    condition     = azurerm_lb_outbound_rule.this["egress"].backend_address_pool_id == azurerm_lb_backend_address_pool.this["web-pool"].id
    error_message = "Outbound rule must target the named backend pool."
  }
}

run "explicit_disable_outbound_snat_wins" {
  variables {
    load_balancing_rules = [
      {
        name                           = "http"
        frontend_ip_configuration_name = "public"
        backend_pool_name              = "web-pool"
        probe_name                     = "http"
        frontend_port                  = 80
        backend_port                   = 80
        disable_outbound_snat          = true
      }
    ]
  }

  assert {
    condition     = azurerm_lb_rule.this["http"].disable_outbound_snat == true
    error_message = "An explicit disable_outbound_snat must override the derived default."
  }
}

run "http_probe_requires_a_request_path" {
  variables {
    health_probes = [
      {
        name     = "http"
        protocol = "Http"
        port     = 80
      }
    ]
  }

  command = plan

  expect_failures = [var.health_probes]
}

run "tcp_probe_rejects_a_request_path" {
  variables {
    health_probes = [
      {
        name         = "tcp"
        protocol     = "Tcp"
        port         = 443
        request_path = "/healthz"
      }
    ]
  }

  command = plan

  expect_failures = [var.health_probes]
}

run "rejects_probe_interval_below_azure_minimum" {
  variables {
    health_probes = [
      {
        name                = "tcp"
        port                = 443
        interval_in_seconds = 1
      }
    ]
  }

  command = plan

  expect_failures = [var.health_probes]
}

run "rejects_ha_ports_rule_with_nonzero_ports" {
  variables {
    load_balancing_rules = [
      {
        name                           = "ha"
        frontend_ip_configuration_name = "public"
        backend_pool_name              = "web-pool"
        probe_name                     = "http"
        protocol                       = "All"
        frontend_port                  = 80
        backend_port                   = 80
      }
    ]
  }

  command = plan

  expect_failures = [var.load_balancing_rules]
}

run "rejects_rule_pointing_at_an_undefined_frontend" {
  variables {
    load_balancing_rules = [
      {
        name                           = "http"
        frontend_ip_configuration_name = "does-not-exist"
        backend_pool_name              = "web-pool"
        probe_name                     = "http"
        frontend_port                  = 80
        backend_port                   = 80
      }
    ]
  }

  command = plan

  expect_failures = [azurerm_lb_rule.this]
}

run "rejects_outbound_rule_on_basic_sku" {
  variables {
    sku = "Basic"
    outbound_rules = [
      {
        name                            = "egress"
        backend_pool_name               = "web-pool"
        frontend_ip_configuration_names = ["public"]
      }
    ]
  }

  command = plan

  expect_failures = [azurerm_lb_outbound_rule.this]
}

run "rejects_outbound_rule_through_an_internal_frontend" {
  variables {
    frontend_ip_configurations = [
      {
        name                 = "public"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/publicIPAddresses/example-pip"
      },
      {
        name      = "internal"
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Network/virtualNetworks/example-vnet/subnets/example-subnet"
      }
    ]
    outbound_rules = [
      {
        name                            = "egress"
        backend_pool_name               = "web-pool"
        frontend_ip_configuration_names = ["internal"]
      }
    ]
  }

  command = plan

  expect_failures = [azurerm_lb_outbound_rule.this]
}
