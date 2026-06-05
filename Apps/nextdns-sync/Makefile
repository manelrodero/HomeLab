.PHONY: build up down restart logs sh image run prune rmi

# Cargar variables desde .env (si existe)
ifneq (,$(wildcard .env))
include .env
export $(shell sed 's/=.*//' .env)
endif

# Nombre del servicio en docker-compose
SERVICE = nextdns-sync

# Ruta del directorio de build
BUILD_DIR = build

# Nombre de la imagen (opcionalmente añade tu namespace)
IMAGE = nextdns-sync:latest

# ----------------------------
# Comandos principales
# ----------------------------

# Construir la imagen usando docker compose
build:
	docker compose build

# Levantar el servicio en segundo plano
up:
	docker compose up -d

# Parar el servicio
down:
	docker compose down

# Reiniciar el servicio
restart:
	docker compose down
	docker compose up -d

# Ver logs en tiempo real
logs:
	docker compose logs -f $(SERVICE)

# Ejecutar un shell dentro del contenedor
sh:
	docker exec -it $(SERVICE) sh

# ----------------------------
# Comandos directos con Docker
# ----------------------------

# Construcción directa sin compose (multi-stage)
image:
	docker build -t $(IMAGE) $(BUILD_DIR)

# Ejecutar la imagen directamente (sin compose)
run:
	docker run --rm -it $(IMAGE)

# ----------------------------
# Limpieza
# ----------------------------

# Eliminar contenedores parados, imágenes huérfanas, etc.
prune:
	docker system prune -f

# Eliminar solo la imagen del proyecto
rmi:
	docker rmi $(IMAGE) || true
