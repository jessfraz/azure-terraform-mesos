resource "azurerm_network_interface" "master-nic0" {
  count = "${var.master_count}"

  name                = "${element(azurerm_resource_group.rg.*.name, 0)}-master-nic${count.index}"
  location            = "${element(azurerm_resource_group.rg.*.location, 0)}"
  resource_group_name = "${element(azurerm_resource_group.rg.*.name, 0)}"

  ip_configuration {
    name                          = "${element(azurerm_resource_group.rg.*.name, 0)}-ipconfig"
    subnet_id                     = "${element(azurerm_subnet.subnet.*.id, 0)}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "${cidrhost("10.0.0.0/16", count.index+5)}"
  }

  tags {
    app  = "nomad-cluster"
    type = "master"
  }
}

######################
# Master VM
######################
resource "azurerm_virtual_machine" "master0" {
  count = "${var.master_count}"

  name                  = "${element(azurerm_resource_group.rg.*.name, 0)}-master${count.index}"
  location              = "${element(azurerm_resource_group.rg.*.location, 0)}"
  resource_group_name   = "${element(azurerm_resource_group.rg.*.name, 0)}"
  vm_size               = "${var.master_vmsize}"
  network_interface_ids = ["${element(azurerm_network_interface.master-nic0.*.id, count.index)}"]

  connection {
    type         = "ssh"
    bastion_host = "${azurerm_public_ip.bastion_public_ip.fqdn}"
    bastion_user = "${var.username}"
    host         = "${element(azurerm_network_interface.master-nic0.*.ip_configuration.0.private_ip_addresses, count.index)}"
    user         = "${var.username}"
    agent        = true
  }

  storage_image_reference {
    publisher = "CoreOS"
    offer     = "CoreOS"
    sku       = "Stable"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${element(azurerm_resource_group.rg.*.name, 0)}-master-osdisk${count.index}"
    managed_disk_type = "StandardSSD_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = "${element(azurerm_resource_group.rg.*.name, 0)}-master${count.index}"
    admin_username = "${var.username}"
    custom_data    = "${file(var.cloud_config_master)}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.username}/.ssh/authorized_keys"
      key_data = "${file(var.public_key_path)}"
    }
  }

  tags {
    app  = "nomad-cluster"
    type = "master"
  }
}
