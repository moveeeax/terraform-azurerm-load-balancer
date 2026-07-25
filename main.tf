locals {
  frontend_names = [for f in var.frontend_ip_configurations : f.name]

  # Backend pools that are covered by an explicit outbound rule. A load
  # balancing rule and an outbound rule cannot both own SNAT for the same
  # backend pool, so rules against these pools default to
  # disable_outbound_snat = true and let the outbound rule do the work.
  pools_with_outbound_rules = distinct([for o in var.outbound_rules : o.backend_pool_name])
}

resource "azurerm_lb" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  dynamic "frontend_ip_configuration" {
    for_each = var.frontend_ip_configurations
    content {
      name                          = frontend_ip_configuration.value.name
      public_ip_address_id          = frontend_ip_configuration.value.public_ip_address_id
      subnet_id                     = frontend_ip_configuration.value.subnet_id
      private_ip_address            = frontend_ip_configuration.value.private_ip_address
      private_ip_address_allocation = frontend_ip_configuration.value.private_ip_address_allocation
      zones                         = frontend_ip_configuration.value.zones
    }
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "this" {
  for_each = toset(var.backend_pool_names)

  name            = each.value
  loadbalancer_id = azurerm_lb.this.id
}

# Azure requires a health probe for every load balancing rule. Without one the
# rule cannot be created, and a load balancer with no rules never forwards any
# traffic to its backend pool.
resource "azurerm_lb_probe" "this" {
  for_each = { for p in var.health_probes : p.name => p }

  name                = each.value.name
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = each.value.protocol
  port                = each.value.port
  request_path        = each.value.request_path
  interval_in_seconds = each.value.interval_in_seconds
  number_of_probes    = each.value.number_of_probes
}

resource "azurerm_lb_rule" "this" {
  for_each = { for r in var.load_balancing_rules : r.name => r }

  name                           = each.value.name
  loadbalancer_id                = azurerm_lb.this.id
  frontend_ip_configuration_name = each.value.frontend_ip_configuration_name
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this[each.value.backend_pool_name].id]
  probe_id                       = azurerm_lb_probe.this[each.value.probe_name].id
  idle_timeout_in_minutes        = each.value.idle_timeout_in_minutes
  load_distribution              = each.value.load_distribution

  disable_outbound_snat = (
    each.value.disable_outbound_snat != null
    ? each.value.disable_outbound_snat
    : contains(local.pools_with_outbound_rules, each.value.backend_pool_name)
  )

  lifecycle {
    precondition {
      condition     = contains(local.frontend_names, each.value.frontend_ip_configuration_name)
      error_message = "Load balancing rule '${each.value.name}' references frontend IP configuration '${each.value.frontend_ip_configuration_name}', which is not defined in var.frontend_ip_configurations."
    }

    precondition {
      condition     = contains(var.backend_pool_names, each.value.backend_pool_name)
      error_message = "Load balancing rule '${each.value.name}' references backend pool '${each.value.backend_pool_name}', which is not defined in var.backend_pool_names."
    }

    precondition {
      condition     = contains([for p in var.health_probes : p.name], each.value.probe_name)
      error_message = "Load balancing rule '${each.value.name}' references health probe '${each.value.probe_name}', which is not defined in var.health_probes."
    }

    # HA ports rules (protocol "All") require both ports to be 0 and are only
    # available on the Standard SKU.
    precondition {
      condition     = each.value.protocol != "All" || (var.sku == "Standard" && each.value.frontend_port == 0 && each.value.backend_port == 0)
      error_message = "Load balancing rule '${each.value.name}' uses protocol \"All\" (HA ports), which requires sku = \"Standard\", frontend_port = 0 and backend_port = 0."
    }
  }
}

# Standard SKU load balancers have no implicit outbound connectivity: default
# outbound access was retired on 2025-09-30, so a backend instance only reaches
# the internet through an outbound rule, an instance-level public IP or a NAT
# gateway. Without one of those the deployment applies cleanly and then has no
# egress at all.
resource "azurerm_lb_outbound_rule" "this" {
  for_each = { for o in var.outbound_rules : o.name => o }

  name                     = each.value.name
  loadbalancer_id          = azurerm_lb.this.id
  protocol                 = each.value.protocol
  backend_address_pool_id  = azurerm_lb_backend_address_pool.this[each.value.backend_pool_name].id
  allocated_outbound_ports = each.value.allocated_outbound_ports
  idle_timeout_in_minutes  = each.value.idle_timeout_in_minutes

  dynamic "frontend_ip_configuration" {
    for_each = each.value.frontend_ip_configuration_names
    content {
      name = frontend_ip_configuration.value
    }
  }

  lifecycle {
    precondition {
      condition     = var.sku == "Standard"
      error_message = "Outbound rule '${each.value.name}' requires sku = \"Standard\"; the Basic and Gateway SKUs do not support outbound rules."
    }

    precondition {
      condition     = contains(var.backend_pool_names, each.value.backend_pool_name)
      error_message = "Outbound rule '${each.value.name}' references backend pool '${each.value.backend_pool_name}', which is not defined in var.backend_pool_names."
    }

    # An outbound rule can only SNAT through a public frontend. Pointing one at
    # an internal frontend is accepted by Terraform and then leaves the backend
    # pool with no egress.
    precondition {
      condition = alltrue([
        for n in each.value.frontend_ip_configuration_names :
        length([
          for f in var.frontend_ip_configurations : f
          if f.name == n && f.public_ip_address_id != null
        ]) == 1
      ])
      error_message = "Outbound rule '${each.value.name}' must reference frontend IP configurations that exist and have public_ip_address_id set; outbound SNAT is not possible through an internal frontend."
    }
  }
}
