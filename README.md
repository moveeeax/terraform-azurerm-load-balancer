# terraform-azurerm-load-balancer

Terraform module that manages an [Azure](https://azure.microsoft.com/) Load
Balancer: frontend IP configurations, backend address pools, health probes,
load balancing rules and outbound rules.

## Why the probe, rule and outbound rule inputs matter

A load balancer that only has frontends and backend pools applies cleanly and
then does nothing. Two things are easy to leave out and hard to notice:

- **Load balancing rules and health probes.** Azure rejects a load balancing
  rule that has no health probe, and without any rule the load balancer never
  forwards traffic to the backend pool.
- **Outbound connectivity.** Default outbound access was retired on
  2025-09-30. On the Standard SKU a backend instance reaches the internet only
  through a load balancing rule's implicit SNAT, an explicit outbound rule, an
  instance-level public IP or a NAT gateway. An internal-only load balancer
  gives its backend pool no egress at all — pair it with a NAT gateway.

The module derives `disable_outbound_snat` for you: a load balancing rule whose
backend pool is covered by an entry in `outbound_rules` gets
`disable_outbound_snat = true` (the outbound rule owns SNAT), and otherwise
`false` (the rule keeps providing implicit SNAT). Set the field explicitly on a
rule to override.

## Usage

```hcl
module "load_balancer" {
  source = "github.com/moveeeax/terraform-azurerm-load-balancer?ref=v1.0.0"

  name                = "web-lb"
  resource_group_name = "prod-rg"
  location            = "eastus"
  sku                 = "Standard"

  frontend_ip_configurations = [
    {
      name                 = "public"
      public_ip_address_id = azurerm_public_ip.lb.id
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

  # Explicit egress for the backend pool.
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
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

An internal load balancer uses `subnet_id` instead of `public_ip_address_id`
and cannot have outbound rules:

```hcl
frontend_ip_configurations = [
  {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address            = "10.0.1.10"
    private_ip_address_allocation = "Static"
    zones                         = ["1", "2", "3"]
  }
]
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| azurerm   | >= 3.0, < 6.0 |

CI validates and tests the module against the 3.0.0 floor and the latest 5.x
release. In azurerm 5.0, `subnet_id` and `public_ip_address_id` on `azurerm_lb`
frontends are no longer Computed; the module always sets them explicitly, so
this has no effect. 6.x is excluded until it has been tested.

The test suite under [`tests/`](tests) additionally needs Terraform or
OpenTofu >= 1.7 for `mock_provider`. That is a test-only requirement; the
module itself still supports 1.5.

## Inputs

| Name                         | Description                                                                  | Type           | Default        | Required |
|------------------------------|------------------------------------------------------------------------------|----------------|----------------|:--------:|
| `name`                       | Name of the load balancer.                                                   | `string`       | n/a            |   yes    |
| `resource_group_name`        | Name of the resource group in which to create the load balancer.             | `string`       | n/a            |   yes    |
| `location`                   | Azure region in which to create the load balancer.                           | `string`       | n/a            |   yes    |
| `sku`                        | SKU of the load balancer. One of Basic, Standard or Gateway.                 | `string`       | `"Standard"`   |    no    |
| `frontend_ip_configurations` | Frontend IP configurations; exactly one of `public_ip_address_id` / `subnet_id` per entry. | `list(object)` | n/a | yes |
| `backend_pool_names`         | Backend address pool names to create.                                        | `list(string)` | `["default"]`  |    no    |
| `health_probes`              | Health probes to create.                                                     | `list(object)` | `[]`           |    no    |
| `load_balancing_rules`       | Load balancing rules to create.                                              | `list(object)` | `[]`           |    no    |
| `outbound_rules`             | Outbound (SNAT) rules to create. Requires `sku = "Standard"`.                | `list(object)` | `[]`           |    no    |
| `tags`                       | Map of tags applied to the load balancer.                                    | `map(string)`  | `{}`           |    no    |

### `frontend_ip_configurations`

| Attribute                       | Type          | Default | Notes                                                        |
|---------------------------------|---------------|---------|--------------------------------------------------------------|
| `name`                          | `string`      | n/a     | Required, unique.                                             |
| `public_ip_address_id`          | `string`      | `null`  | Public frontend. Mutually exclusive with `subnet_id`.         |
| `subnet_id`                     | `string`      | `null`  | Internal frontend. Mutually exclusive with `public_ip_address_id`. |
| `private_ip_address`            | `string`      | `null`  | Requires `subnet_id` and `private_ip_address_allocation = "Static"`. |
| `private_ip_address_allocation` | `string`      | `null`  | `Static` or `Dynamic`.                                        |
| `zones`                         | `set(string)` | `null`  | Zone pinning for an internal frontend. Standard SKU only.     |

### `health_probes`

| Attribute             | Type     | Default | Notes                                                     |
|-----------------------|----------|---------|-----------------------------------------------------------|
| `name`                | `string` | n/a     | Required, unique.                                          |
| `port`                | `number` | n/a     | Required, 1-65535.                                         |
| `protocol`            | `string` | `"Tcp"` | `Tcp`, `Http` or `Https`.                                  |
| `request_path`        | `string` | `null`  | Required for `Http`/`Https`, must be unset for `Tcp`.      |
| `interval_in_seconds` | `number` | `15`    | Minimum 5.                                                 |
| `number_of_probes`    | `number` | `2`     | Minimum 1.                                                 |

### `load_balancing_rules`

| Attribute                        | Type     | Default | Notes                                                            |
|----------------------------------|----------|---------|------------------------------------------------------------------|
| `name`                           | `string` | n/a     | Required, unique.                                                 |
| `frontend_ip_configuration_name` | `string` | n/a     | Must name an entry in `frontend_ip_configurations`.               |
| `backend_pool_name`              | `string` | n/a     | Must name an entry in `backend_pool_names`.                       |
| `probe_name`                     | `string` | n/a     | Must name an entry in `health_probes`.                            |
| `frontend_port`                  | `number` | n/a     | 1-65535, or 0 for HA ports.                                       |
| `backend_port`                   | `number` | n/a     | 1-65535, or 0 for HA ports.                                       |
| `protocol`                       | `string` | `"Tcp"` | `Tcp`, `Udp` or `All`. `All` (HA ports) needs Standard and port 0. |
| `idle_timeout_in_minutes`        | `number` | `4`     | 4-100.                                                            |
| `load_distribution`              | `string` | `null`  | `Default`, `SourceIP` or `SourceIPProtocol`.                      |
| `disable_outbound_snat`          | `bool`   | derived | Defaults to `true` when an outbound rule covers the pool.         |

### `outbound_rules`

| Attribute                         | Type           | Default | Notes                                                    |
|-----------------------------------|----------------|---------|-----------------------------------------------------------|
| `name`                            | `string`       | n/a     | Required, unique.                                          |
| `backend_pool_name`               | `string`       | n/a     | Must name an entry in `backend_pool_names`.                |
| `frontend_ip_configuration_names` | `list(string)` | n/a     | Must name public frontends; SNAT needs a public IP.        |
| `protocol`                        | `string`       | `"All"` | `Tcp`, `Udp` or `All`.                                     |
| `allocated_outbound_ports`        | `number`       | `null`  | 0 (automatic) to 64000. Provider default when unset.       |
| `idle_timeout_in_minutes`         | `number`       | `4`     | 4-100.                                                     |

## Outputs

| Name                        | Description                                              |
|-----------------------------|----------------------------------------------------------|
| `id`                        | ID of the load balancer.                                 |
| `name`                      | Name of the load balancer.                               |
| `frontend_ip_configuration` | Frontend IP configuration blocks.                        |
| `private_ip_addresses`      | Private IPs assigned to internal frontends.              |
| `backend_address_pool_ids`  | Map of backend address pool names to their IDs.          |
| `health_probe_ids`          | Map of health probe names to their IDs.                  |
| `load_balancing_rule_ids`   | Map of load balancing rule names to their IDs.           |
| `outbound_rule_ids`         | Map of outbound rule names to their IDs.                 |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test
tflint --recursive
```

## License

[MIT](LICENSE)
