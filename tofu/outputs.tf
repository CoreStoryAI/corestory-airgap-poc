output "private_ip_address" {
  description = "Private-only address of the Plot VM."
  value       = azurerm_network_interface.airgap.private_ip_address
}

output "network_controls" {
  description = "Controls that enforce the Azure-side egress boundary."
  value = {
    public_ip                      = false
    nat_gateway                    = false
    subnet_default_outbound_access = false
    nsg_outbound_default           = "deny"
  }
}
