terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}
locals {
  jupyter-count     = data.coder_parameter.jupyter.value == "false" ? 0 : 1
  code-server-count = data.coder_parameter.code-server.value == "false" ? 0 : 1
  ngc-version       = "24.04"
  username          = data.coder_workspace_owner.me.name
}

data "coder_parameter" "ram" {
  name         = "ram"
  display_name = "RAM (GB)"
  description  = "Choose amount of RAM (min: 16 GB, max: 128 GB)"
  type         = "number"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/memory.svg"
  mutable      = true
  default      = "32"
  order        = 2
  validation {
    min = 16
    max = 128
  }
}

data "coder_parameter" "framework" {
  name         = "framework"
  display_name = "Deeplearning Framework"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/memory.svg"
  description  = "Choose your preffered framework"
  type         = "string"
  default      = "pytorch"
  mutable      = false
  order        = 1
  option {
    name        = "Nvidia PyTorch"
    description = "Nvidia NGC PyTorch"
    value       = "pytorch"
    icon        = "https://raw.githubusercontent.com/matifali/logos/main/pytorch.svg"
  }
  option {
    name        = "Nvidia Tensorflow"
    description = "Nvidia NGC Tensorflow"
    value       = "tensorflow"
    icon        = "https://raw.githubusercontent.com/matifali/logos/main/tensorflow.svg"
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_image.deeplearning.id
  icon        = data.coder_parameter.framework.option[index(data.coder_parameter.framework.option.*.value, data.coder_parameter.framework.value)].icon
  item {
    key   = "Framework"
    value = data.coder_parameter.framework.option[index(data.coder_parameter.framework.option.*.value, data.coder_parameter.framework.value)].name
  }
  item {
    key   = "NGC Version"
    value = local.ngc-version
  }
  item {
    key   = "RAM (GB)"
    value = data.coder_parameter.ram.value
  }
}

data "coder_parameter" "code-server" {
  name         = "code-server"
  display_name = "VS Code Web"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/code.svg"
  description  = "Do you want VS Code Web?"
  type         = "bool"
  mutable      = true
  default      = "false"
  order        = 3
}

data "coder_parameter" "jupyter" {
  name         = "jupyter"
  display_name = "Jupyter Lab"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/jupyter.svg"
  description  = "Do you want Jupyter Lab?"
  type         = "bool"
  mutable      = true
  default      = "false"
  order        = 4
}

data "coder_parameter" "share_vscode_web" {
  name         = "share_vscode_web"
  display_name = "Share VS Code Web"
  description  = "Allow sharing VS Code Web"
  type         = "bool"
  mutable      = true
  default      = "false"
  order        = 5
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# jupyter
resource "coder_app" "jupyter" {
  count        = local.jupyter-count
  agent_id     = coder_agent.main.id
  display_name = "Jupyter Lab"
  slug         = "jupyter"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/jupyter.svg"
  url          = "http://localhost:8888/"
  subdomain    = true
  share        = "owner"
}

# resource "coder_app" "code-server" {
#   count        = local.code-server-count
#   agent_id     = coder_agent.main.id
#   display_name = "VS Code Web"
#   slug         = "code-server"
#   url          = "http://localhost:8000?folder=/home/${local.username}/data/"
#   icon         = "https://raw.githubusercontent.com/matifali/logos/main/code.svg"
#   subdomain    = true
#   share        = data.coder_parameter.share_vscode_web.value == "false" ? "owner" : "authenticated"
# }
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/${local.username}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "filebrowser" {
  count        = 1
  agent_id     = coder_agent.main.id
  display_name = "File Browser"
  slug         = "filebrowser"
  url          = "http://localhost:8080/"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/database.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080/health"
    interval  = 5
    threshold = 6
  }
}

resource "coder_agent" "main" {
  arch                   = "amd64"
  os                     = "linux"
  # startup_script_behavior = "non-blocking"
  startup_script         = <<EOT
    #!/bin/bash
    set -euo pipefail

    # Create user data directory
    mkdir -p /home/${local.username}/data
    # make user share directory
    mkdir -p /home/${local.username}/share

    # Install and start filebrowser
    echo "Installing filebrowser"
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    echo "Starting filebrowser"
    filebrowser --noauth --root /home/${local.username}/data >./filebrowser.log --baseurl /@${local.username}/${data.coder_workspace.me.name}/filebrowser 2>&1 &
  
    # Start jupyter
    if [ ${data.coder_parameter.jupyter.value} == true ];
    then
      echo "Starting Jupyter Lab"
      /usr/local/bin/jupyter lab --no-browser --LabApp.token='' --LabApp.password='' >/dev/null 2>&1 &
    fi

    # Install and satrt VS code-server
    if [ ${data.coder_parameter.code-server.value} == true ];
    then
      echo "Installing VS Code Web"      
      # Install the latest code-server.
      # Append "--version x.x.x" to install a specific version of code-server.
      curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server

      # Start code-server in the background.
      /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &

    fi

    # Personalize
    if [ -x ~/personalize ]; then
      ~/personalize 2>&1 | tee -a ~/.personalize.log
    elif [ -f ~/personalize ]; then
      echo "~/personalize is not executable, skipping..." | tee -a ~/.personalize.log
    fi

    EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  metadata {
    display_name = "CPU Usage Workspace"
    interval     = 10
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
  }

  metadata {
    display_name = "RAM Usage Workspace"
    interval     = 10
    key          = "1_ram_usage"
    script       = "coder stat mem"
  }

  metadata {
    display_name = "CPU Usage Host"
    interval     = 10
    key          = "2_cpu_usage"
    script       = "coder stat cpu --host"
  }

  metadata {
    display_name = "RAM Usage Host"
    interval     = 10
    key          = "3_ram_usage"
    script       = "coder stat mem --host"
  }

  metadata {
    display_name = "GPU Usage"
    interval     = 10
    key          = "4_gpu_usage"
    script       = <<EOT
      nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | awk '{printf "%s%%", $1}'
    EOT
  }

  metadata {
    display_name = "GPU Memory Usage"
    interval     = 10
    key          = "5_gpu_memory_usage"
    script       = <<EOT
      nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits | awk '{printf "%s%%", $1}'
    EOT
  }

  metadata {
    display_name = "Disk Usage"
    interval     = 600
    key          = "6_disk_usage"
    script       = "coder stat disk $HOME"
  }

  metadata {
    display_name = "Word of the Day"
    interval     = 86400
    key          = "7_word_of_the_day"
    script       = <<EOT
      #!/bin/bash
      curl -o - --silent https://www.merriam-webster.com/word-of-the-day 2>&1 | awk ' $0 ~ "Word of the Day: [A-z]+" { print $5; exit }'
    EOT
  }
}

resource "docker_image" "deeplearning" {
  name = "matifali/ngc-${data.coder_parameter.framework.value}"
  build {
    context    = "./images"
    dockerfile = "${data.coder_parameter.framework.value}.Dockerfile"
    tag        = ["matifali/ngc-${data.coder_parameter.framework.value}:${local.ngc-version}", "matifali/ngc-${data.coder_parameter.framework.value}:latest"]
    build_args = {
      "NGC_VERSION" = "${local.ngc-version}"
      "USERNAME"    = "${local.username}"
    }
    pull_parent = true
  }
  triggers = {
    file_sha1 = sha1(join("", [for f in fileset(path.module, "images/${data.coder_parameter.framework.value}.Dockerfile") : filesha1(f)]))
  }
  keep_locally = true
}

#Volumes Resources
#home_volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

#usr_volume
resource "docker_volume" "usr_volume" {
  # name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-usr"
  name = "coder-${data.coder_workspace.me.id}-usr"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

#etc_volume
resource "docker_volume" "etc_volume" {
  # name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-etc"
  name = "coder-${data.coder_workspace.me.id}-etc"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

#opt_volume
resource "docker_volume" "opt_volume" {
  # name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-opt"
  name = "coder-${data.coder_workspace.me.id}-opt"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.deeplearning.image_id
  memory   = data.coder_parameter.ram.value * 1024
  gpus     = "all"
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  # dns      = ["1.1.1.1"]
  command  = ["sh", "-c", coder_agent.main.init_script]
  env      = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  restart  = "unless-stopped"

  devices {
    host_path = "/dev/nvidia0"
  }
  devices {
    host_path = "/dev/nvidiactl"
  }
  devices {
    host_path = "/dev/nvidia-uvm-tools"
  }
  devices {
    host_path = "/dev/nvidia-uvm"
  }
  devices {
    host_path = "/dev/nvidia-modeset"
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  # ipc_mode = "host"

  # users home directory
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/usr/"
    volume_name    = docker_volume.usr_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/etc/"
    volume_name    = docker_volume.etc_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/opt/"
    volume_name    = docker_volume.opt_volume.name
    read_only      = false
  }
  # users data directory
  volumes {
    container_path = "/home/${local.username}/data/"
    host_path      = "/data/${data.coder_workspace.me.name}/"
    read_only      = false
  }
  # shared data directory
  volumes {
    container_path = "/home/${local.username}/share"
    host_path      = "/data/share/"
    read_only      = true
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "coder_metadata" "workspace" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[count.index].id
  daily_cost  = 50
}
