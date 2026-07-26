terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      # Актуальный провайдер. telmate/proxmox давно не развивается — не используй его.
      # Из РФ реестр недоступен (403), поэтому провайдер ставится из filesystem mirror
      # (скачивается напрямую с GitHub bpg/terraform-provider-proxmox). Ограничение
      # ослаблено до ">=", чтобы подошла свежая версия из зеркала.
      source  = "bpg/proxmox"
      version = ">= 0.66"
    }
  }

  # Раскомментировать, когда поднимешь MinIO (этап 5) — и получишь ещё один
  # сильный пункт в резюме: "state в S3-совместимом хранилище с версионированием".
  #
  # backend "s3" {
  #   endpoints                   = { s3 = "http://192.168.10.240:9000" }
  #   bucket                      = "tf-state"
  #   key                         = "homelab/proxmox/terraform.tfstate"
  #   region                      = "us-east-1"
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   skip_metadata_api_check     = true
  #   skip_s3_checksum            = true
  #   use_path_style              = true
  #   use_lockfile                = true
  # }
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token

  # Самоподписанный сертификат Proxmox. В проде так делать нельзя —
  # там ставится нормальный сертификат и insecure убирается.
  insecure = true

  # Провайдеру нужен SSH к хосту для импорта облачного образа как диска VM
  # и операций со сниппетами. Ходит на хост под root по ключу control-ноды.
  # Ключ без пароля (сгенерирован с -N ""), поэтому file() читает его напрямую.
  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
