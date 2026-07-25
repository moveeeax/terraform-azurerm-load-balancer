output "id" {
  description = "ID of the load balancer."
  value       = azurerm_lb.this.id
}

output "name" {
  description = "Name of the load balancer."
  value       = azurerm_lb.this.name
}

output "frontend_ip_configuration" {
  description = "Frontend IP configuration blocks of the load balancer."
  value       = azurerm_lb.this.frontend_ip_configuration
}

output "private_ip_addresses" {
  description = "Private IP addresses assigned to the load balancer's internal frontends."
  value       = azurerm_lb.this.private_ip_addresses
}

output "backend_address_pool_ids" {
  description = "Map of backend address pool names to their IDs."
  value       = { for k, v in azurerm_lb_backend_address_pool.this : k => v.id }
}

output "health_probe_ids" {
  description = "Map of health probe names to their IDs."
  value       = { for k, v in azurerm_lb_probe.this : k => v.id }
}

output "load_balancing_rule_ids" {
  description = "Map of load balancing rule names to their IDs."
  value       = { for k, v in azurerm_lb_rule.this : k => v.id }
}

output "outbound_rule_ids" {
  description = "Map of outbound rule names to their IDs."
  value       = { for k, v in azurerm_lb_outbound_rule.this : k => v.id }
}
