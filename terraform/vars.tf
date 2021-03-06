variable "prefix" {}

variable "location" {
  description = "The location/region where the resources are created. Changing this forces a new resource to be created."
  default     = "westus2"
}

variable "locations" {
  default = [
    "westus2",
    "eastus",
    "eastus2",
  ]
}

variable "vnet_address_space" {
  default = [
    "10.0.0.0/16",
    "10.1.0.0/16",
    "10.2.0.0/16",
  ]
}

variable "rg" {
  description = "The name of the resource group in which to create the resources."
  default     = "cluster"
}

variable "orchestrator" {
  description = "The orchestrator for the cluster."
  default     = "nomad"
}

variable "master_count" {
  description = "Number of master nodes to create."
  default     = 5
}

variable "agent_count" {
  description = "Number of master nodes to create."
  default     = 18
}

variable "master_vmsize" {
  description = "Specifies the size of the virtual machine for the masters."
  default     = "Standard_DS3_v2"
}

variable "agent_vmsize" {
  description = "Specifies the size of the virtual machine for the agents."
  default     = "Standard_DS3_v2"
}

variable "username" {
  description = "The system administrator user name."
  default     = "vmuser"
}

variable "public_key_path" {
  description = "Path to your SSH Public Key"
  default     = "~/.azure/ssh_key"
}

# This file is generated and populated with certs from the Makefile at runtime.
variable "cloud_config_master" {
  default = "../_tmp/nomad/cloud-config-master.yml"
}

# This file is generated and populated with certs from the Makefile at runtime.
variable "cloud_config_agent" {
  default = "../_tmp/nomad/cloud-config-agent.yml"
}

# This file is generated and populated with certs from the Makefile at runtime.
variable "cloud_config_bastion" {
  default = "../_tmp/nomad/cloud-config-bastion.yml"
}

variable "image_publisher" {
  description = "Virtual machine image publisher."
  default     = "CoreOS"
}

variable "image_sku" {
  description = "Virtual machine image sku."
  default     = "Stable"
}

variable "image_version" {
  description = "Virtual machine image version."
  default     = "latest"
}

variable "client_id" {}

variable "client_secret" {}

variable "tenant_id" {}

variable "subscription_id" {}

provider "azurerm" {
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
  subscription_id = "${var.subscription_id}"
}
