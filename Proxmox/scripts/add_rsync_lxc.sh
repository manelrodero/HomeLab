#!/bin/bash
clear

# Add RSYNC Mount Point v1.2 (2026-01-17)

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
# Validar BACKUP_RSYNC_DIR
# ============================
if [ -z "$BACKUP_RSYNC_DIR" ]; then
    echo -e "${RED}Error: La variable BACKUP_RSYNC_DIR no está definida en proxmox.env.${NC}"
    exit 1
fi

# ============================
# Pedir ID de LXC
# ============================
echo -e "${GREEN}Introduce el ID del contenedor LXC:${NC}"
read -p "> " CTID

if ! pct status "$CTID" &>/dev/null; then
    echo -e "${RED}Error: El contenedor $CTID no existe.${NC}"
    exit 1
fi

# Obtener nombre del contenedor
CTNAME=$(pct config "$CTID" | grep -E '^hostname:' | awk '{print $2}')

if [ -z "$CTNAME" ]; then
    echo -e "${RED}No se pudo obtener el nombre del contenedor $CTID.${NC}"
    exit 1
fi

# ============================
# Crear directorio de backup
# ============================
BACKUP_DIR="${BACKUP_RSYNC_DIR}/${CTID}-${CTNAME}"

if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo -e "${CYAN}Directorio creado:${NC} $BACKUP_DIR"
else
    echo -e "${CYAN}El directorio ya existe:${NC} $BACKUP_DIR"
fi

# Cambiar propietario (UID/GID mapeados)
chown 100000:101000 "$BACKUP_DIR"

# ============================
# Comprobar si ya existe un mount point igual
# ============================
CONFIG=$(pct config "$CTID")

# 1) ¿Ya existe un mpX con ese BACKUP_DIR?
if echo "$CONFIG" | grep -q "$BACKUP_DIR"; then
    echo -e "${RED}Este contenedor YA tiene un mount point usando:${NC}"
    echo "  $BACKUP_DIR"
    echo -e "${CYAN}No se añade un duplicado.${NC}"
    exit 0
fi

# 2) ¿Ya existe un mpX con mp=/mnt/rsync?
if echo "$CONFIG" | grep -q "mp=/mnt/rsync"; then
    echo -e "${RED}Este contenedor YA tiene un mount point en /mnt/rsync.${NC}"
    echo -e "${CYAN}No se añade un duplicado.${NC}"
    exit 0
fi

# ============================
# Buscar siguiente índice mpX
# ============================
NEXT_MP=$(echo "$CONFIG" | grep -E '^mp[0-9]:' | awk -F: '{print $1}' | sort -V | tail -n1)

if [ -z "$NEXT_MP" ]; then
    MP_INDEX="mp0"
else
    NUM=$(echo "$NEXT_MP" | sed 's/mp//')
    NEXT=$((NUM+1))
    MP_INDEX="mp${NEXT}"
fi

# ============================
# Añadir punto de montaje
# ============================
pct set "$CTID" -${MP_INDEX} "$BACKUP_DIR,mp=/mnt/rsync"

echo -e "${GREEN}Configuración completada para el contenedor $CTID ($CTNAME).${NC}"
echo -e "${CYAN}Se ha añadido el punto de montaje en ${MP_INDEX} → /mnt/rsync${NC}"
