locals {
  common_tags = ["terraform", "k3s", "homelab"]

  # Диски MinIO: декартово произведение "нода × хранилище".
  # 3 ноды × 2 SSD = 6 дисков, по одному с каждого физического устройства на ноду.
  # Внутри VM они станут /dev/sdb и /dev/sdc.
  node_data_disks = {
    for pair in setproduct(keys(var.nodes), range(length(var.data_datastores))) :
    "${pair[0]}-${pair[1]}" => {
      node      = pair[0]
      index     = pair[1]
      datastore = var.data_datastores[pair[1]]
    }
  }
}

# Облачный образ Ubuntu скачивается прямо на хранилище Proxmox.
# Готовить шаблон вручную через qm не нужно — в этом смысл декларативного подхода.
resource "proxmox_virtual_environment_download_file" "ubuntu" {
  content_type = "iso"
  datastore_id = var.image_datastore
  node_name    = var.pve_node
  url          = var.ubuntu_image_url
  file_name    = "ubuntu-noble-cloudimg-amd64.img"
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "node" {
  # for_each, а не count: удаление ноды из середины map не пересоздаёт остальные.
  # С count индексы сдвинулись бы и Terraform снёс бы всё, что стоит после удалённой.
  for_each = var.nodes

  name        = each.key
  description = "k3s ${each.value.role} — управляется Terraform, вручную не править"
  tags        = concat(local.common_tags, [each.value.role])
  node_name   = var.pve_node
  vm_id       = each.value.vmid

  # QEMU guest agent нужен, чтобы Terraform видел реальные IP машины
  # и чтобы корректно работало graceful shutdown.
  agent {
    enabled = true
  }

  stop_on_destroy = true

  cpu {
    cores = each.value.cores
    # type = host прокидывает флаги реального процессора: заметно быстрее,
    # но ломает живую миграцию между разным железом. Для одного хоста — то что надо.
    type = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Системный диск — из скачанного облачного образа, на SSD1
  disk {
    datastore_id = var.system_datastore
    file_id      = proxmox_virtual_environment_download_file.ubuntu.id
    interface    = "scsi0"
    size         = var.system_disk_size
    discard      = "on"
    ssd          = true
  }

  # Диски под MinIO — по одному с каждого физического SSD.
  # Отдельные устройства: свой I/O, не конкурируют с системным диском,
  # и MinIO получает по сути сырое блочное устройство.
  dynamic "disk" {
    for_each = var.data_datastores
    content {
      datastore_id = disk.value
      interface    = "scsi${disk.key + 1}" # scsi1, scsi2 → /dev/sdb, /dev/sdc
      size         = var.data_disk_size
      discard      = "on"
      ssd          = true
      file_format  = "raw"
    }
  }

  network_device {
    bridge = var.network_bridge
  }

  initialization {
    datastore_id = var.system_datastore

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.subnet_prefix}"
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.vm_username
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  operating_system {
    type = "l26"
  }

  # Последовательная консоль — чтобы видеть загрузку в веб-интерфейсе Proxmox,
  # когда сеть ещё не поднялась. Экономит время при отладке cloud-init.
  serial_device {}

  lifecycle {
    ignore_changes = [
      # Proxmox иногда сам меняет описание диска после импорта образа — не реагируем.
      disk[0].file_id,
    ]
  }
}
