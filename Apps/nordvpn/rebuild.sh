#!/bin/bash

# Nombre de la imagen
IMAGE_NAME="nordvpn-custom"

echo "🔍  Buscando contenedores que usen la imagen '$IMAGE_NAME'..."
CONTAINERS=$(docker ps -a -q --filter ancestor=$IMAGE_NAME)

if [ -n "$CONTAINERS" ]; then
    echo "🗑️  Eliminando contenedores:"
    echo "$CONTAINERS"
    docker rm -f $CONTAINERS
else
    echo "✅  No hay contenedores usando la imagen."
fi

echo "🧹  Eliminando imágenes antiguas de '$IMAGE_NAME'..."
docker images -q $IMAGE_NAME | xargs -r docker rmi -f

echo "🔨  Construyendo nueva imagen '$IMAGE_NAME'..."
# docker build --no-cache -t $IMAGE_NAME .
docker compose build --no-cache

echo "✅  Imagen reconstruida con éxito."
