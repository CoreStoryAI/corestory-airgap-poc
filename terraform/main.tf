locals {
  tags = {
    managed-by = "terraform"
    purpose    = "plot-airgap-poc"
  }
}

resource "azurerm_resource_group" "airgap" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "airgap" {
  name                = "${var.vm_name}-vnet"
  location            = azurerm_resource_group.airgap.location
  resource_group_name = azurerm_resource_group.airgap.name
  address_space       = ["10.80.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "airgap" {
  name                              = "airgap"
  resource_group_name               = azurerm_resource_group.airgap.name
  virtual_network_name              = azurerm_virtual_network.airgap.name
  address_prefixes                  = ["10.80.0.0/26"]
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_network_security_group" "airgap" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.airgap.location
  resource_group_name = azurerm_resource_group.airgap.name
  tags                = local.tags

  dynamic "security_rule" {
    for_each = var.management_source_cidr == "" ? [] : [var.management_source_cidr]
    content {
      name                       = "ssh-from-private-operator"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "10.80.0.10/32"
    }
  }

  security_rule {
    name                       = "deny-all-ingress"
    priority                   = 4095
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-egress"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "airgap" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.airgap.location
  resource_group_name = azurerm_resource_group.airgap.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.airgap.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.80.0.10"
  }
}

resource "azurerm_network_interface_security_group_association" "airgap" {
  network_interface_id      = azurerm_network_interface.airgap.id
  network_security_group_id = azurerm_network_security_group.airgap.id
}

resource "azurerm_linux_virtual_machine" "airgap" {
  name                            = var.vm_name
  computer_name                   = var.vm_name
  location                        = azurerm_resource_group.airgap.location
  resource_group_name             = azurerm_resource_group.airgap.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.airgap.id]
  source_image_id                 = var.source_image_id
  patch_assessment_mode           = "ImageDefault"
  patch_mode                      = "ImageDefault"
  provision_vm_agent              = false
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 80
  }

  boot_diagnostics {}

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "offline_media" {
  managed_disk_id    = var.offline_media_disk_id
  virtual_machine_id = azurerm_linux_virtual_machine.airgap.id
  lun                = 10
  caching            = "ReadOnly"
}
