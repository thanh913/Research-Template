#!/usr/bin/env bash
# Global one-time machine bootstrap for ML research
# Works on Ubuntu ≥ 20.04 (x86_64 or aarch64)

set -euo pipefail

log() { printf "\e[1;34m[setup]\e[0m %s\n" "$*"; }

# ---- 0. sudo helper ----------------------------------------------------------
[ "$(id -u)" -eq 0 ] && SUDO="" || SUDO="sudo"

# ---- 1. APT packages ---------------------------------------------------------
APT_PKGS=(
  build-essential git curl wget ca-certificates
  tmux mosh htop nvtop
)

log "Updating apt index…"
$SUDO apt-get update -qq

MISSING=()
for p in "${APT_PKGS[@]}"; do dpkg -s "$p" &>/dev/null || MISSING+=("$p"); done
if (( ${#MISSING[@]} )); then
  log "Installing: ${MISSING[*]} …"
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${MISSING[@]}"
else
  log "All apt packages already present."
fi

# ---- 2. pipx & CLI goodies ---------------------------------------------------
if ! command -v pipx &>/dev/null; then
  log "Installing pipx…"
  python3 -m pip install --user --upgrade pip pipx
  ~/.local/bin/pipx ensurepath
  export PATH="$HOME/.local/bin:$PATH"
else
  log "pipx already installed."
fi

for tool in gpustat ntfy-wrapper; do
  if pipx list | grep -q "$tool"; then
    log "$tool already installed via pipx."
  else
    log "pipx install $tool"
    pipx install "$tool"
  fi
done

# ---- 3. Miniconda + fast solver ---------------------------------------------
if [ -d "$HOME/miniconda" ] && [ -f "$HOME/miniconda/bin/conda" ]; then
  log "Miniconda already installed."
elif ! command -v conda &>/dev/null; then
  log "Installing Miniconda…"
  TMPDIR=$(mktemp -d)
  wget -qO "$TMPDIR/conda.sh" https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-$(uname -m).sh
  bash "$TMPDIR/conda.sh" -b -p "$HOME/miniconda"
  rm -rf "$TMPDIR"
  conda init bash zsh
else
  log "Conda already available in PATH."
fi

# Ensure conda is available in current shell
if [ -f "$HOME/miniconda/bin/conda" ]; then
  eval "$("$HOME/miniconda/bin/conda" shell.bash hook)"
elif command -v conda &>/dev/null; then
  # conda is available but not from miniconda, try to initialize it
  eval "$(conda shell.bash hook)"
fi

if command -v conda &>/dev/null; then
  log "Enabling libmamba solver…"
  conda config --set solver libmamba
  log "Disabling auto-activation of base conda environment…"
  conda config --set auto_activate_base false
else
  log "Warning: conda not available, skipping libmamba solver configuration."
fi

# ---- 4. Done ----------------------------------------------------------------
log "Global setup complete 🎉  Open a new terminal or 'source ~/.bashrc'."
