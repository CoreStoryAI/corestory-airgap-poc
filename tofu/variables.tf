variable "subscription_id" {
  type        = string
  description = "Azure subscription that owns the isolated proof of concept."
}

variable "location" {
  type        = string
  description = "Azure region for every resource."
  default     = "westus2"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group created for the proof of concept."
  default     = "plot-airgap-poc"
}

variable "vm_name" {
  type        = string
  description = "Name of the isolated virtual machine."
  default     = "plot-airgap-poc"
}

variable "vm_size" {
  type        = string
  description = "CPU-oriented default; select a larger memory or GPU SKU for larger models."
  default     = "Standard_D8s_v5"
}

variable "admin_username" {
  type        = string
  description = "Local administrative account baked into the image."
  default     = "plotadmin"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "Public key required by Azure VM creation; strict runtime filtering prevents network SSH replies."

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH Ed25519 or RSA public key."
  }
}

variable "source_image_id" {
  type        = string
  description = "Immutable Azure Compute Gallery image version prepared by image/build-image.sh."

  validation {
    condition     = can(regex("/versions/[^/]+$", var.source_image_id))
    error_message = "source_image_id must identify an immutable Azure Compute Gallery image version."
  }
}

variable "offline_media_disk_id" {
  type        = string
  description = "Managed-disk ID containing the checksum-pinned offline bundle and no secrets; the guest importer requires a read-only mount."
}

variable "management_source_cidr" {
  type        = string
  description = "Optional private operator CIDR allowed to reach SSH; leave empty to deny all inbound traffic."
  default     = ""
}
