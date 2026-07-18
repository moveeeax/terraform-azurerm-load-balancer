variable "name" {
  description = "Name of the load balancer."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group in which to create the load balancer."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the load balancer."
  type        = string
}

variable "sku" {
  description = "SKU of the load balancer. One of Basic, Standard or Gateway."
  type        = string
  default     = "Standard"
}

variable "frontend_ip_configurations" {
  description = "List of frontend IP configurations. Provide either a public_ip_address_id or a subnet_id per entry."
  type = list(object({
    name                          = string
    public_ip_address_id          = optional(string, null)
    subnet_id                     = optional(string, null)
    private_ip_address            = optional(string, null)
    private_ip_address_allocation = optional(string, null)
  }))

  validation {
    condition     = length(var.frontend_ip_configurations) > 0
    error_message = "At least one frontend IP configuration must be provided."
  }
}

variable "backend_pool_names" {
  description = "List of backend address pool names to create on the load balancer."
  type        = list(string)
  default     = ["default"]
}

variable "tags" {
  description = "Map of tags applied to the load balancer."
  type        = map(string)
  default     = {}
}
