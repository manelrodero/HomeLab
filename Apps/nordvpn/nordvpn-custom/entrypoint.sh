#!/bin/bash

# entrypoint.sh v47 - 2025-08-20, (c) Manel Rodero & Copilot (tratándolo con cariño y persistencia ;-)

set -e

# 🕒 Timestamp para logs
timestamp() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a /var/log/nordvpn/entrypoint.log
}

# 🔍 Validación de variables de entorno
validate_env_vars() {
  timestamp "🔍 Validando variables de entorno necesarias..."

  local missing=()
  for var in NORDVPN_TOKEN NORDVPN_CONNECT NORDVPN_TECHNOLOGY NORDVPN_NETWORK NORDVPN_DNS NORDVPN_P2P; do
    [ -z "${!var}" ] && missing+=("$var")
  done

  if [ ${#missing[@]} -ne 0 ]; then
    timestamp "❌ Faltan variables obligatorias: ${missing[*]}. Abortando."
    exit 1
  fi

  timestamp "✅ Todas las variables necesarias están presentes."
}

# 🧹 Limpieza de entorno residual
clean_previous_state() {
  if [ -d /run/nordvpn ]; then
    timestamp "🧹 Borrando directorio '/run/nordvpn' residual..."
    rm -rf /run/nordvpn
  fi
}

# 🔐 Inicio del daemon NordVPN
start_nordvpn_daemon() {
  if pgrep nordvpnd >/dev/null; then
    timestamp "🟢 El daemon 'nordvpnd' ya está en ejecución."
  else
    timestamp "🔐 Iniciando daemon 'nordvpnd'..."
    /etc/init.d/nordvpn start
  fi
}

# ⏳ Espera del socket
wait_for_socket() {
  local max_wait=60
  local waited=0
  local sleep_interval=10

  timestamp "🔄 Esperando disponibilidad de 'nordvpnd.sock'..."

  while [ ! -S /run/nordvpn/nordvpnd.sock ]; do
    timestamp "⏳ Aún no disponible. Esperando..."
    sleep $sleep_interval
    waited=$((waited + sleep_interval))
    if [ "$waited" -ge "$max_wait" ]; then
      timestamp "❌ El socket no apareció en $max_wait segundos. Abortando."
      exit 1
    fi
  done

  timestamp "🟢 Socket disponible. El daemon 'nordvpnd' está listo."
}

# 🔑 Inicio de sesión
login_nordvpn() {
  if ! nordvpn account | grep -q "Logged in"; then
    timestamp "🔑 Iniciando sesión en NordVPN mediante token..."
    if echo n | nordvpn login --token "$NORDVPN_TOKEN" > /dev/null 2>&1; then
      timestamp "✅ Sesión iniciada correctamente."
    else
      timestamp "⚠️ Inicio de sesión fallido o sesión ya existente."
    fi
  else
    timestamp "🟢 Ya hay una sesión iniciada en NordVPN."
  fi
}

# ⚙️ Configuración de parámetros
configure_nordvpn() {
  timestamp "⚙️ Aplicando configuración de NordVPN..."

  nordvpn allowlist add subnet "$NORDVPN_NETWORK" || true
  nordvpn set technology "$NORDVPN_TECHNOLOGY"
  nordvpn set killswitch enabled
  nordvpn set dns $NORDVPN_DNS || true
  nordvpn set analytics disable
  nordvpn set autoconnect enable
}

# 🌍 Conexión inicial
connect_nordvpn() {
  if ! nordvpn status | grep -q "Connected"; then
    if [ "$NORDVPN_P2P" = "S" ]; then
      timestamp "🌍 Conectando a ubicación '$NORDVPN_CONNECT' (P2P)..."
      nordvpn connect -group p2p "$NORDVPN_CONNECT"
    else
      timestamp "🌍 Conectando a ubicación '$NORDVPN_CONNECT' (Standard)..."
      nordvpn connect "$NORDVPN_CONNECT"
    fi
  fi
}

# 🧹 Desconexión limpia
graceful_shutdown() {
  local signal="$1"
  timestamp "🧹 Recibida señal '$signal'. Comprobando estado de NordVPN..."

  if nordvpn status | grep -q "Connected"; then
    nordvpn disconnect
    timestamp "🔴 NordVPN desconectada."
  fi

  nordvpn logout --persist-token || timestamp "⚠️ Final de sesión fallido o sesión no existente."
  timestamp "🔴 NordVPN finalizada."
  exit 0
}

# 🛡️ Vigilancia de conexión
monitor_connection() {
  timestamp "🛡️ NordVPN activa. Vigilando estado de conexión..."

  local max_retries=5
  local retry_count=0
  local sleep_interval=10

  while true; do
    if ! nordvpn status | grep -q "Connected"; then
      timestamp "⚠️ NordVPN desconectada. Reintentando conexión... ($((retry_count+1))/$max_retries)"
      nordvpn connect "$NORDVPN_CONNECT"
      retry_count=$((retry_count+1))
      if [ "$retry_count" -ge "$max_retries" ]; then
        timestamp "❌ Se alcanzó el número máximo de reintentos. Abortando."
        exit 1
      fi
    else
      retry_count=0
    fi
    sleep $sleep_interval &
    wait $!
  done
}

# 🚦 Captura de señales
trap 'graceful_shutdown SIGTERM' SIGTERM
trap 'graceful_shutdown SIGINT' SIGINT

# 🚀 Ejecución principal
timestamp "🚀 Ejecutando Docker ENTRYPOINT..."

validate_env_vars
clean_previous_state
start_nordvpn_daemon
wait_for_socket
login_nordvpn
configure_nordvpn
connect_nordvpn
monitor_connection
