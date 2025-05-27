#!/usr/bin/env bash
# One-time machine bootstrap for Qwen/VeRL work on GH200
# Works on Ubuntu ≥ 20.04 (aarch64 or x86_64)

set -euo pipefail
log() { printf "\e[1;34m[setup]\e[0m %s\n" "$*"; }

IMAGE_TAG="thanh913/verl-gh200:0.8.5"
CONTAINER_NAME="verl-gh200"

# ──────────────────────────────────────────────────────────── 0. base utils ──
APT_PKGS=(curl wget tmux mosh htop nvtop build-essential ca-certificates)

log "Updating apt index…" ; sudo apt-get update -qq
MISSING=(); for p in "${APT_PKGS[@]}"; do dpkg -s "$p" &>/dev/null || MISSING+=("$p"); done
(( ${#MISSING[@]} )) && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING[@]}"

# ──────────────────────────────────────────────────────────── 1. Docker ▒ GPU ─
if ! command -v docker &>/dev/null; then
  log "Installing Docker Engine…"
  curl -fsSL https://get.docker.com | sh
fi

if ! dpkg -s nvidia-container-toolkit &>/dev/null; then
  log "Installing NVIDIA Container Toolkit…"
  distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
  curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo tee /usr/share/keyrings/nvidia-container-toolkit.gpg >/dev/null
  curl -s -L https://nvidia.github.io/libnvidia-container/"$distribution"/libnvidia-container.list | \
    sed 's#deb #deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] #' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
fi

# ──────────────────────────────────────────────────────────── 2. pull image ──
log "Pulling $IMAGE_TAG (first time only)…"
sudo docker pull "$IMAGE_TAG"

# ──────────────────────────────────────────────────────────── 3. helper shim ─
cat <<'EOS' | sudo tee /usr/local/bin/run-verl.sh >/dev/null
#!/usr/bin/env bash
# Launch the VeRL GH200 container
set -e
IMAGE="thanh913/verl-gh200:0.8.5"
# bind host cwd → /workspace, HF cache, big shared-memory
docker run --gpus all -it --rm \
  -v "$PWD":/workspace \
  -v "$HOME/.cache":/home/researcher/.cache \
  --shm-size=16g \
  --name verl-gh200 \
  "$IMAGE" bash
EOS
sudo chmod +x /usr/local/bin/run-verl.sh

# ──────────────────────────────────────────────────────────── done ───────────
log "Setup complete 🎉  Use 'run-verl.sh' to enter the container."
