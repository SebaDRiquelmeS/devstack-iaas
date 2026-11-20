variable "libvirt_uri" {
  description = "Conexión de libvirt en el hipervisor."
  type        = string
  default     = "qemu:///system"
}

variable "hostname" {
  description = "Nombre del dominio libvirt y del nodo Rocky."
  type        = string
  default     = "rockystack"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.hostname)) && !endswith(var.hostname, "-")
    error_message = "Usa un nombre DNS corto en minúsculas."
  }
}

variable "memory_mb" {
  description = "Memoria de la VM en MiB."
  type        = number
  default     = 8192
}

variable "cpu" {
  description = "Número de vCPU."
  type        = number
  default     = 6
}

variable "disk_size_gib" {
  description = "Tamaño del disco de trabajo de Rocky en GiB."
  type        = number
  default     = 65
}

variable "pool_path" {
  description = "Directorio absoluto para el pool; por defecto, un subdirectorio del almacén de libvirt."
  type        = string
  default     = null
}

variable "rocky_image" {
  description = "URL HTTPS o ruta absoluta a una imagen oficial Rocky 9 GenericCloud x86_64."
  type        = string
  default     = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
}

variable "ssh_public_key_path" {
  description = "Archivo de clave SSH pública para la cuenta rocky."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "management_network" {
  description = "Red libvirt existente con DHCP y salida a Internet."
  type        = string
  default     = "default"
}

variable "enable_netstack" {
  description = "Crea una red aislada tipo netstack y conecta una segunda interfaz para Neutron."
  type        = bool
  default     = true
}

variable "netstack_cidr" {
  description = "Subred IPv4 /24 aislada para las IP flotantes de Neutron."
  type        = string
  default     = "172.24.4.0/24"

  validation {
    condition     = can(cidrnetmask(var.netstack_cidr)) && endswith(var.netstack_cidr, "/24")
    error_message = "Usa una subred IPv4 con prefijo /24."
  }
}
