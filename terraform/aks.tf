data "http" "current_ip" {
  url = "https://ipinfo.io/ip"
}

data "namep_azure_name" "aksrg" {
  name     = "aks"
  type     = "azurerm_resource_group"
}

data "namep_azure_name" "aks" {
  name     = var.environment
  type     = "azurerm_kubernetes_cluster"
}

resource "azurerm_resource_group" "aksrg" {
  name = data.namep_azure_name.aksrg.result
  location = var.location
  tags = local.common_tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  resource_group_name = azurerm_resource_group.aksrg.name
  name                = data.namep_azure_name.aks.result
  location            = azurerm_resource_group.aksrg.location
  tags                = local.common_tags
  dns_prefix          = var.environment
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                 = "${var.environment}default"
    node_count           = var.default_pool_node_count
    vm_size              = var.default_pool_node_type
    os_disk_size_gb      = 30
    os_disk_type         = "Ephemeral"
    vnet_subnet_id       = azurerm_subnet.aks.id
    type                 = "VirtualMachineScaleSets"
    orchestrator_version = var.kubernetes_version
    availability_zones   = var.availability_zones
    node_labels = {
      "environment"   = var.environment
      "nodepoolos"    = "linux"
    }
    tags = local.common_tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  role_based_access_control {
    enabled = true
  }

  api_server_authorized_ip_ranges = [
    "${chomp(data.http.current_ip.body)}/32"
  ]

}

resource "azurerm_kubernetes_cluster_node_pool" "win" {
  availability_zones    = var.availability_zones
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  name                  = "${var.environment}win"
  os_disk_size_gb       = 30
  os_disk_type          = "Ephemeral"
  os_type               = "Windows"
  node_count            = var.default_pool_node_count
  vm_size               = var.default_pool_node_type
  vnet_subnet_id        = azurerm_subnet.aks.id
  node_labels = {
    "environment"   = var.environment
    "nodepoolos"    = "windows"
  }
  tags = local.common_tags
}

# AKS access to ACR
resource "azurerm_role_assignment" "acrpull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

#Calico role, maybe this should be actually vnet_contributor instead of contributor, but following https://docs.microsoft.com/en-us/azure/aks/use-network-policies
resource "azurerm_role_assignment" "network_contributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
