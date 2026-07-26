output "node_ips" {
  description = "IP-адреса нод кластера"
  value       = { for name, cfg in var.nodes : name => cfg.ip }
}

output "servers" {
  description = "Ноды control-plane (k3s server)"
  value       = [for name, cfg in var.nodes : cfg.ip if cfg.role == "server"]
}

output "agents" {
  description = "Рабочие ноды (k3s agent)"
  value       = [for name, cfg in var.nodes : cfg.ip if cfg.role == "agent"]
}

# Готовый инвентарь для Ansible — чтобы не переписывать IP руками в двух местах.
# Использование:  terraform output -raw ansible_inventory > ../ansible/inventory.ini
output "ansible_inventory" {
  description = "Инвентарь Ansible, сгенерированный из топологии"
  value = <<-EOT
    [k3s_first]
    ${[for name, cfg in var.nodes : "${name} ansible_host=${cfg.ip}" if cfg.role == "server"][0]}

    [k3s_servers]
    %{~for name, cfg in var.nodes~}
    %{~if cfg.role == "server"~}
    ${name} ansible_host=${cfg.ip}
    %{~endif~}
    %{~endfor~}

    [k3s_agents]
    %{~for name, cfg in var.nodes~}
    %{~if cfg.role == "agent"~}
    ${name} ansible_host=${cfg.ip}
    %{~endif~}
    %{~endfor~}

    [k3s_cluster:children]
    k3s_servers
    k3s_agents

    [k3s_cluster:vars]
    ansible_user=${var.vm_username}
    ansible_python_interpreter=/usr/bin/python3
  EOT
}
