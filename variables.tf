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
  description = "SKU of the load balancer. One of Basic, Standard or Gateway. The Basic SKU was retired on 2025-09-30 and supports neither availability zones nor outbound rules; new deployments should stay on the Standard default."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Gateway"], var.sku)
    error_message = "sku must be one of Basic, Standard or Gateway (case sensitive)."
  }
}

variable "frontend_ip_configurations" {
  description = <<-EOT
    List of frontend IP configurations. Each entry must set exactly one of
    public_ip_address_id (public frontend) or subnet_id (internal frontend).
  EOT
  type = list(object({
    name                          = string
    public_ip_address_id          = optional(string, null)
    subnet_id                     = optional(string, null)
    private_ip_address            = optional(string, null)
    private_ip_address_allocation = optional(string, null)
    zones                         = optional(set(string), null)
  }))

  validation {
    condition     = length(var.frontend_ip_configurations) > 0
    error_message = "At least one frontend IP configuration must be provided."
  }

  validation {
    condition     = length(distinct([for f in var.frontend_ip_configurations : f.name])) == length(var.frontend_ip_configurations)
    error_message = "Frontend IP configuration names must be unique."
  }

  validation {
    condition = alltrue([
      for f in var.frontend_ip_configurations :
      (f.public_ip_address_id != null) != (f.subnet_id != null)
    ])
    error_message = "Each frontend IP configuration must set exactly one of public_ip_address_id or subnet_id."
  }

  validation {
    condition = alltrue([
      for f in var.frontend_ip_configurations :
      f.private_ip_address == null || (f.subnet_id != null && f.private_ip_address_allocation == "Static")
    ])
    error_message = "A frontend IP configuration that pins private_ip_address must also set subnet_id and private_ip_address_allocation = \"Static\"."
  }

  validation {
    condition = alltrue([
      for f in var.frontend_ip_configurations :
      f.private_ip_address_allocation == null || contains(["Static", "Dynamic"], coalesce(f.private_ip_address_allocation, "Dynamic"))
    ])
    error_message = "private_ip_address_allocation must be either Static or Dynamic."
  }
}

variable "backend_pool_names" {
  description = "List of backend address pool names to create on the load balancer."
  type        = list(string)
  default     = ["default"]

  validation {
    condition     = length(distinct(var.backend_pool_names)) == length(var.backend_pool_names)
    error_message = "Backend pool names must be unique."
  }
}

variable "health_probes" {
  description = <<-EOT
    Health probes to create on the load balancer. Every load balancing rule
    needs one: Azure rejects a rule without a probe. Http and Https probes
    require request_path; Tcp probes must not set it.
  EOT
  type = list(object({
    name                = string
    port                = number
    protocol            = optional(string, "Tcp")
    request_path        = optional(string, null)
    interval_in_seconds = optional(number, 15)
    number_of_probes    = optional(number, 2)
  }))
  default = []

  validation {
    condition     = length(distinct([for p in var.health_probes : p.name])) == length(var.health_probes)
    error_message = "Health probe names must be unique."
  }

  validation {
    condition     = alltrue([for p in var.health_probes : contains(["Tcp", "Http", "Https"], p.protocol)])
    error_message = "Health probe protocol must be one of Tcp, Http or Https (case sensitive)."
  }

  validation {
    condition = alltrue([
      for p in var.health_probes :
      p.protocol == "Tcp" ? p.request_path == null : p.request_path != null
    ])
    error_message = "Http and Https health probes must set request_path (for example \"/healthz\"); Tcp probes must leave it unset."
  }

  validation {
    condition     = alltrue([for p in var.health_probes : p.port >= 1 && p.port <= 65535])
    error_message = "Health probe port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for p in var.health_probes : p.interval_in_seconds >= 5])
    error_message = "Health probe interval_in_seconds must be at least 5."
  }

  validation {
    condition     = alltrue([for p in var.health_probes : p.number_of_probes >= 1])
    error_message = "Health probe number_of_probes must be at least 1."
  }
}

variable "load_balancing_rules" {
  description = <<-EOT
    Load balancing rules to create. Without at least one rule the load balancer
    accepts no traffic, so a module call that only defines frontends and backend
    pools deploys successfully and then serves nothing.

    disable_outbound_snat defaults to true for rules whose backend pool is
    covered by an entry in var.outbound_rules (the outbound rule owns SNAT) and
    to false otherwise (the rule provides implicit outbound SNAT). Set it
    explicitly to override.
  EOT
  type = list(object({
    name                           = string
    frontend_ip_configuration_name = string
    backend_pool_name              = string
    probe_name                     = string
    frontend_port                  = number
    backend_port                   = number
    protocol                       = optional(string, "Tcp")
    idle_timeout_in_minutes        = optional(number, 4)
    load_distribution              = optional(string, null)
    disable_outbound_snat          = optional(bool, null)
  }))
  default = []

  validation {
    condition     = length(distinct([for r in var.load_balancing_rules : r.name])) == length(var.load_balancing_rules)
    error_message = "Load balancing rule names must be unique."
  }

  validation {
    condition     = alltrue([for r in var.load_balancing_rules : contains(["Tcp", "Udp", "All"], r.protocol)])
    error_message = "Load balancing rule protocol must be one of Tcp, Udp or All (case sensitive)."
  }

  validation {
    condition = alltrue([
      for r in var.load_balancing_rules :
      r.protocol == "All" ? (r.frontend_port == 0 && r.backend_port == 0) : (r.frontend_port >= 1 && r.frontend_port <= 65535 && r.backend_port >= 1 && r.backend_port <= 65535)
    ])
    error_message = "Load balancing rule ports must be between 1 and 65535, or both 0 when protocol is \"All\" (HA ports)."
  }

  validation {
    condition = alltrue([
      for r in var.load_balancing_rules :
      r.load_distribution == null || contains(["Default", "SourceIP", "SourceIPProtocol"], coalesce(r.load_distribution, "Default"))
    ])
    error_message = "load_distribution must be one of Default, SourceIP or SourceIPProtocol."
  }

  validation {
    condition     = alltrue([for r in var.load_balancing_rules : r.idle_timeout_in_minutes >= 4 && r.idle_timeout_in_minutes <= 100])
    error_message = "Load balancing rule idle_timeout_in_minutes must be between 4 and 100."
  }
}

variable "outbound_rules" {
  description = <<-EOT
    Outbound rules to create. Standard SKU load balancers give their backend
    instances no implicit outbound internet access (default outbound access was
    retired on 2025-09-30), so backend VMs need an outbound rule, an
    instance-level public IP or a NAT gateway. Requires sku = "Standard" and a
    public frontend.
  EOT
  type = list(object({
    name                            = string
    backend_pool_name               = string
    frontend_ip_configuration_names = list(string)
    protocol                        = optional(string, "All")
    allocated_outbound_ports        = optional(number, null)
    idle_timeout_in_minutes         = optional(number, 4)
  }))
  default = []

  validation {
    condition     = length(distinct([for o in var.outbound_rules : o.name])) == length(var.outbound_rules)
    error_message = "Outbound rule names must be unique."
  }

  validation {
    condition     = alltrue([for o in var.outbound_rules : contains(["Tcp", "Udp", "All"], o.protocol)])
    error_message = "Outbound rule protocol must be one of Tcp, Udp or All (case sensitive)."
  }

  validation {
    condition     = alltrue([for o in var.outbound_rules : length(o.frontend_ip_configuration_names) > 0])
    error_message = "Each outbound rule must reference at least one frontend IP configuration."
  }

  validation {
    condition = alltrue([
      for o in var.outbound_rules :
      o.allocated_outbound_ports == null || (coalesce(o.allocated_outbound_ports, 1024) >= 0 && coalesce(o.allocated_outbound_ports, 1024) <= 64000)
    ])
    error_message = "allocated_outbound_ports must be between 0 (automatic) and 64000."
  }

  validation {
    condition     = alltrue([for o in var.outbound_rules : o.idle_timeout_in_minutes >= 4 && o.idle_timeout_in_minutes <= 100])
    error_message = "Outbound rule idle_timeout_in_minutes must be between 4 and 100."
  }
}

variable "tags" {
  description = "Map of tags applied to the load balancer."
  type        = map(string)
  default     = {}
}
