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

output "backend_address_pool_ids" {
  description = "Map of backend address pool names to their IDs."
  value       = { for k, v in azurerm_lb_backend_address_pool.this : k => v.id }
}
