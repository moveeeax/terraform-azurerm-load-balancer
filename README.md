# terraform-azurerm-load-balancer

Terraform module that manages an [Azure](https://azure.microsoft.com/) Load
Balancer. Frontend IP configurations are supplied as a list and rendered through
a dynamic block, and one or more backend address pools are created alongside the
load balancer for attaching virtual machines or scale sets.

## Usage

```hcl
module "load_balancer" {
  source = "github.com/cybercapybara/terraform-azurerm-load-balancer"

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

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| azurerm   | >= 3.0   |

## Inputs

| Name                         | Description                                                            | Type           | Default        | Required |
|------------------------------|------------------------------------------------------------------------|----------------|----------------|:--------:|
| `name`                       | Name of the load balancer.                                             | `string`       | n/a            |   yes    |
| `resource_group_name`        | Name of the resource group in which to create the load balancer.       | `string`       | n/a            |   yes    |
| `location`                   | Azure region in which to create the load balancer.                     | `string`       | n/a            |   yes    |
| `sku`                        | SKU of the load balancer. One of Basic, Standard or Gateway.           | `string`       | `"Standard"`   |    no    |
| `frontend_ip_configurations` | List of frontend IP configurations.                                    | `list(object)` | n/a            |   yes    |
| `backend_pool_names`         | List of backend address pool names to create.                          | `list(string)` | `["default"]`  |    no    |
| `tags`                       | Map of tags applied to the load balancer.                              | `map(string)`  | `{}`           |    no    |

## Outputs

| Name                        | Description                                     |
|-----------------------------|-------------------------------------------------|
| `id`                        | ID of the load balancer.                        |
| `name`                      | Name of the load balancer.                      |
| `frontend_ip_configuration` | Frontend IP configuration blocks.               |
| `backend_address_pool_ids`  | Map of backend address pool names to their IDs. |

## License

[MIT](LICENSE)
