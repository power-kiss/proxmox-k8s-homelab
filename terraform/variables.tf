variable "pve_endpoint" {
  type        = string
  description = "URL API Proxmox, например https://192.168.10.230:8006/"
}

variable "pve_api_token" {
  type        = string
  sensitive   = true
  description = "Токен вида 'terraform@pve!provider=xxxxxxxx-xxxx-...'"
}

variable "pve_node" {
  type        = string
  description = "Имя ноды Proxmox (см. в веб-интерфейсе, обычно pve)"
  default     = "pve"
}

variable "system_datastore" {
  type        = string
  description = "Хранилище под системные диски VM (SSD1, создаётся инсталлятором)"
  default     = "local-lvm"
}

variable "data_datastores" {
  type        = list(string)
  description = <<-EOT
    Хранилища под диски MinIO — по одному на физический SSD.
    Каждая нода получит по одному диску из КАЖДОГО хранилища списка.
    3 ноды × 2 хранилища = 6 дисков в erasure set.
  EOT
  default = ["ssd-data-1", "ssd-data-2"]

  validation {
    condition     = length(var.data_datastores) >= 1
    error_message = "Нужно хотя бы одно хранилище под данные."
  }
}

variable "image_datastore" {
  type        = string
  description = "Хранилище для скачанного облачного образа (нужен content type 'iso')"
  default     = "local"
}

variable "network_bridge" {
  type        = string
  description = "Сетевой мост Proxmox"
  default     = "vmbr0"
}

variable "subnet_prefix" {
  type        = number
  description = "Длина префикса подсети LAN"
  default     = 24
}

variable "gateway" {
  type        = string
  description = "Шлюз по умолчанию"
  default     = "192.168.10.1"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS-серверы для нод"
  default     = ["192.168.10.1", "1.1.1.1"]
}

variable "ssh_public_key_path" {
  type        = string
  description = "Путь к публичному SSH-ключу, который положим в cloud-init"
  default     = "~/.ssh/id_ed25519.pub"
}

variable "vm_username" {
  type        = string
  description = "Пользователь, создаваемый cloud-init"
  default     = "ubuntu"
}

variable "ubuntu_image_url" {
  type        = string
  description = "URL облачного образа Ubuntu"
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "system_disk_size" {
  type        = number
  description = <<-EOT
    Размер системного диска ноды, ГБ. Живут на local-lvm (thin-пул 137 ГБ на Samsung).
    3 ноды × 40 ГБ = 120 ГБ — влезает в пул с запасом. ОС ~8, образы ~10, PostgreSQL local-path.
  EOT
  default = 40

  validation {
    condition     = var.system_disk_size >= 30
    error_message = "Меньше 30 ГБ не хватит на образы контейнеров, логи и тома local-path."
  }
}

variable "data_disk_size" {
  type        = number
  description = <<-EOT
    Размер каждого диска MinIO, ГБ. Живут на ssd-data-1/ssd-data-2 (по ~119 ГБ, DEXP 118 ГБ).
    3 ноды × 35 ГБ = 105 ГБ на диск — без переподписки thin-пула.
  EOT
  default = 35
}

variable "nodes" {
  description = <<-EOT
    Топология кластера. Ключ map — имя ноды (оно же hostname).
    role: server = control-plane + etcd + рабочая нагрузка, agent = только worker.

    На i3-8100 (4 потока) держим 3 ноды: все совмещают control-plane и нагрузку.
    Три сервера дают кворум etcd и переживают потерю одной ноды.
  EOT

  type = map(object({
    vmid   = number
    ip     = string
    cores  = number
    memory = number
    role   = string
  }))

  default = {
    "k3s-1" = { vmid = 201, ip = "192.168.10.231", cores = 3, memory = 8192, role = "server" }
    "k3s-2" = { vmid = 202, ip = "192.168.10.232", cores = 3, memory = 8192, role = "server" }
    "k3s-3" = { vmid = 203, ip = "192.168.10.233", cores = 3, memory = 8192, role = "server" }
  }

  validation {
    condition     = length([for n in var.nodes : n if n.role == "server"]) % 2 == 1
    error_message = "Число нод с ролью server должно быть нечётным (1, 3, 5) — иначе etcd не соберёт кворум."
  }

  validation {
    condition     = length([for n in var.nodes : n if n.role == "server"]) >= 3
    error_message = "Для HA нужно минимум 3 сервера. С одним сервером кластер переживает 0 отказов."
  }
}
