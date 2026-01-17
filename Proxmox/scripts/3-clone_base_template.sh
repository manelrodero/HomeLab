#!/bin/bash
clear

# Clone LXC Template v3.1 (2026-01-17)

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
# Colores
# ============================
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
NC='\033[0m'

# ============================
# PASO 1: CLONAR
# ============================
echo -e "${GREEN}Introduce el nombre del nuevo contenedor:${NC}"
read -p "> " lxcname

while true; do
  echo -e "${GREEN}Introduce el CT ID de la plantilla:${NC}"
  read -p "> " ct_id

  if ! pct status "$ct_id" &>/dev/null; then
    echo -e "${RED}Error: El CT ID $ct_id no existe.${NC}"
    continue
  fi

  if ! pct config "$ct_id" | grep -q "^template: 1"; then
    echo -e "${RED}Error: El CT ID $ct_id no es una plantilla.${NC}"
    continue
  fi

  break
done

while true; do
  echo -e "${GREEN}Introduce el CT ID del nuevo contenedor:${NC}"
  read -p "> " new_ct_id

  if pct status "$new_ct_id" &>/dev/null; then
    echo -e "${RED}Error: El CT ID $new_ct_id ya existe.${NC}"
  else
    break
  fi
done

echo -e "${CYAN}Clonando la plantilla...${NC}"
pct clone "$ct_id" "$new_ct_id" --hostname "$lxcname" --full

# ============================
# PASO 2: RSYNC (opcional)
# ============================
if [ "${BACKUP_RSYNC}" = "S" ]; then
    echo -e "${CYAN}Configurando carpeta RSYNC...${NC}"

    mkdir -p "/backups/rsync/$new_ct_id-$lxcname"
    chown 100000:101000 "/backups/rsync/$new_ct_id-$lxcname"
    chmod 770 "/backups/rsync/$new_ct_id-$lxcname"

    pct set "$new_ct_id" -mp0 "/backups/rsync/$new_ct_id-$lxcname,mp=/mnt/rsync"
else
    echo -e "${CYAN}RSYNC desactivado (BACKUP_RSYNC != S).${NC}"
fi

# ============================
# PASO 3: DIRECCIÓN IP
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

echo -e "${CYAN}Configurando red...${NC}"
pct set "$new_ct_id" -net0 name=eth0,bridge=vmbr0,ip="$ip",gw="$GATEWAY"

# ============================
# PASO 4: HARDWARE
# ============================
while true; do
  echo -e "${GREEN}Introduce el número de cores (ej: 2):${NC}"
  read -p "> " cores
  if [[ "$cores" =~ ^[1-9][0-9]*$ ]]; then
    break
  else
    echo -e "${RED}Número inválido. Debe ser un entero positivo.${NC}"
  fi
done

while true; do
  echo -e "${GREEN}Introduce la memoria RAM en MB (ej: 1024):${NC}"
  read -p "> " memory
  if [[ "$memory" =~ ^[1-9][0-9]*$ ]]; then
    break
  else
    echo -e "${RED}Cantidad inválida. Debe ser un entero positivo.${NC}"
  fi
done

while true; do
  echo -e "${GREEN}Introduce la SWAP en MB (ej: 512):${NC}"
  read -p "> " swap
  if [[ "$swap" =~ ^[0-9]+$ ]]; then
    break
  else
    echo -e "${RED}Cantidad inválida. Debe ser un número entero (puede ser 0).${NC}"
  fi
done

echo -e "${CYAN}Aplicando configuración de hardware...${NC}"
pct set "$new_ct_id" -cores "$cores" -memory "$memory" -swap "$swap"

# ============================
# PASO 5: DISCO
# ============================
current_gb=$(pct config "$new_ct_id" | grep -oP 'rootfs:.*?,size=\K[0-9]+(?=G)')

echo -e "${CYAN}Tamaño actual del disco de $new_ct_id: ${GREEN}${current_gb}G${NC}"

while true; do
  echo -e "${GREEN}Introduce el nuevo tamaño del disco en GB (>= ${current_gb}):${NC}"
  read -p "> " disk_size

  if [[ "$disk_size" =~ ^[1-9][0-9]*$ ]]; then
    if (( disk_size >= current_gb )); then
      break
    else
      echo -e "${RED}Debe ser mayor o igual que el tamaño actual (${current_gb}G).${NC}"
    fi
  else
    echo -e "${RED}Tamaño inválido. Debe ser un entero positivo.${NC}"
  fi
done

if (( disk_size > current_gb )); then
    echo -e "${CYAN}Ampliando el disco del contenedor...${NC}"
    pct resize "$new_ct_id" rootfs "${disk_size}G"
else
    echo -e "${CYAN}El tamaño es igual al actual. No se realiza resize.${NC}"
fi

# ============================
# PASO 6: INICIAR
# ============================
pct config "$new_ct_id"
pct start "$new_ct_id"

echo -e "${GREEN}Contenedor ${new_ct_id} creado y configurado correctamente.${NC}"
