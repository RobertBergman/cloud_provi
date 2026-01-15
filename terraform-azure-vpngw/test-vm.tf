# =============================================================================
# Test VM for Connectivity Testing
# =============================================================================
# Ubuntu VM with dual-stack networking for testing IPv4 and IPv6 connectivity
# to the on-premises simulation.
# =============================================================================

# -----------------------------------------------------------------------------
# Network Interface (Dual-Stack)
# -----------------------------------------------------------------------------

resource "azurerm_network_interface" "test_vm" {
  name                = "nic-test-vm-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # IPv4 configuration
  ip_configuration {
    name                          = "ipconfig-v4"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(local.workload_subnet_ipv4, 100) # 10.1.1.100
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.test_vm.id
  }

  # IPv6 configuration
  ip_configuration {
    name                          = "ipconfig-v6"
    subnet_id                     = azurerm_subnet.workload.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv6"
  }

  tags = {
    Environment = var.environment
  }
}

# Public IP for SSH access
resource "azurerm_public_ip" "test_vm" {
  name                = "pip-test-vm-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Test VM
# -----------------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "test" {
  name                = "vm-test-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.test_vm_size
  admin_username      = var.test_vm_admin_username

  network_interface_ids = [azurerm_network_interface.test_vm.id]

  admin_ssh_key {
    username   = var.test_vm_admin_username
    public_key = var.test_vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Cloud-init to install testing tools
  custom_data = base64encode(<<-EOF
    #cloud-config
    package_update: true
    packages:
      - net-tools
      - traceroute
      - mtr-tiny
      - tcpdump
      - iputils-ping
      - dnsutils

    runcmd:
      - echo "Test VM ready for connectivity testing"
      - ip addr show
      - ip -6 addr show
  EOF
  )

  tags = {
    Environment = var.environment
    Purpose     = "VPN connectivity testing"
  }
}
