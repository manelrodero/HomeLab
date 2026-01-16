#!/bin/bash
clear

# Create base for LXC Template v1.9 (2026-01-16)

# ============================
# Cargar configuración externa
# ============================
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/proxmox.env"

if [ -f "$CONFIG_FILE" ]; then
    set -o allexport
    source "$CONFIG_FILE"
    set +o allexport
else
    echo "⚠️  No se encontró proxmox.env. Usa proxmox.env.example como plantilla."
    echo "   $CONFIG_FILE"
    exit 1
fi

# ============================
# Validar SSH_PUBLIC_KEY
# ============================
SSH_KEY_OPTION=""

if [ -n "${SSH_PUBLIC_KEY+x}" ] && [ -n "$SSH_PUBLIC_KEY" ]; then
    if [ -f "$SSH_PUBLIC_KEY" ]; then
        SSH_KEY_OPTION="--ssh-public-keys $SSH_PUBLIC_KEY"
    else
        echo "❌ Error: SSH_PUBLIC_KEY está definida pero el fichero no existe:"
        echo "   $SSH_PUBLIC_KEY"
        exit 1
    fi
fi

# ============================
# Colores
# ============================
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
NC='\033[0m'

# ============================
# Solicitar datos al usuario
# ============================
echo -e "${GREEN}Introduce el nombre de la plantilla:${NC}"
read -p "> " lxcname

while true; do
  echo -e "${GREEN}Introduce el CT ID:${NC}"
  read -p "> " ct_id
  if pct list | awk '{print $1}' | grep -qw "$ct_id"; then
    echo -e "${RED}Error: El CT ID $ct_id ya existe.${NC}"
  else
    break
  fi
done

while true; do
  echo -e "${GREEN}Introduce el password de 'root' (mínimo 5 caracteres):${NC}"
  read -s -p "> " password1
  echo
  echo -e "${GREEN}Confirma el password de 'root':${NC}"
  read -s -p "> " password2
  echo

  if [ "$password1" != "$password2" ]; then
      echo -e "${RED}Error: Los passwords no coinciden.${NC}"
      continue
  fi

  if [ "${#password1}" -lt 5 ]; then
      echo -e "${RED}Error: El password debe tener al menos 5 caracteres.${NC}"
      continue
  fi

  password="$password1"
  break
done

# ============================
# Validación del último octeto
# ============================
valid_last_octet() {
  [[ "$1" =~ ^[0-9]{1,3}$ ]] || return 1
  (( $1 >= 1 && $1 <= 254 )) || return 1
  return 0
}

while true; do
  echo -e "${GREEN}Introduce el último octeto de la IP (${NETWORK}.x):${NC}"
  read -p "> " last_octet

  if valid_last_octet "$last_octet"; then
      ip="${NETWORK}.${last_octet}${NETMASK}"
      break
  else
      echo -e "${RED}Valor inválido. Debe ser un número entre 1 y 254.${NC}"
  fi
done

# ============================
# Crear contenedor
# ============================
echo -e "${CYAN}Creando el contenedor ${ct_id}...${NC}"

pct create "$ct_id" local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --ostype debian --arch amd64 \
  --hostname "$lxcname" --unprivileged 1 \
  --password "$password" $SSH_KEY_OPTION \
  --storage "$STORAGE" --rootfs "$STORAGE:$ROOTFS_SIZE" \
  --cores "$CORES" \
  --memory "$MEMORY" --swap "$SWAP" \
  --net0 name=eth0,bridge=vmbr0,firewall=1,ip="$ip",gw="$GATEWAY" \
  --features nesting=1,keyctl=1 \
  --onboot 1 \
  --start 0
