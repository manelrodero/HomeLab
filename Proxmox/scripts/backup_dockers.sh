#!/bin/bash

# Backup Dockers with Rsync v1.3 (2025-08-18)

# Obtener el nombre de la maquina
HOSTNAME=$(hostname)

# Directorio base
BASE_DIR=~/dockers
LOG_FILE="$BASE_DIR/backup_dockers.log"
ERR_FILE="$BASE_DIR/rsync_errors.log"

# Limpiar el log de errores anterior
if [ -f "$ERR_FILE" ]; then
        rm "$ERR_FILE"
fi

# Timestamp inicial
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$START_TIME -------------------- BEGIN --------------------" >> "$LOG_FILE"

# Recorrer cada subdirectorio
for dir in "$BASE_DIR"/*/; do
    # Verificar si es un directorio
    if [ -d "$dir" ]; then
        cd "$dir" || continue

        # Si existe compose.yaml, realizar las operaciones
        if [ -f "compose.yaml" ]; then
            # Nombre del subdirectorio actual
            DIR_NAME=$(basename "$dir")

            # Timestamp inicial
            START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
            echo "$START_TIME Procesando directorio '$DIR_NAME'" >> "$LOG_FILE"

            # Parar los contenedores
            docker compose down

            # Preparar el destino para rsync
            DEST_DIR="/mnt/rsync/$DIR_NAME"
            mkdir -p "$DEST_DIR"

            # Ejecutar rsync
            sudo rsync -av --delete "$dir" "$DEST_DIR" 2>> "$ERR_FILE"
            if [ $? -eq 0 ]; then
                RESULT="OK"
                rm "$ERR_FILE"
            else
                RESULT="ERROR"
            fi

            # Levantar los contenedores
            docker compose up -d

            # Timestamp final con el resultado
            END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
            echo "$END_TIME - Rsync $RESULT" >> "$LOG_FILE"
        fi
    fi
done

# Timestamp inicial
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "$START_TIME --------------------  END  --------------------" >> "$LOG_FILE"
