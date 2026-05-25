# Tailscale en Docker (Raspberry Pi 4)

Este repositorio contiene la configuración necesaria para desplegar **Tailscale** en un contenedor Docker utilizando `network_mode: host`. 

Este enfoque óptimo permite utilizar el dispositivo como enrutador de subred (**Subnet Router**) y como nodo de salida (**Exit Node**) hacia Internet.

## Objetivos

* **Subnet Router:** Permitir el acceso remoto a toda la red local sin necesidad de instalar Tailscale en cada dispositivo.
* **Exit Node:** Actuar como una VPN completa para tunelizar de forma segura todo el tráfico de Internet de mis dispositivos remotos a través de la conexión de mi hogar.

## Pre-requisitos (En el servidor Host)

Para que Tailscale pueda enrutar el tráfico de otros dispositivos, el kernel de Linux de la Raspberry Pi 4 debe tener activado el reenvío de IP (**IP forwarding**).

Editar el archivo de configuración `/etc/sysctl.conf`:

```bash
sudo nano /etc/sysctl.conf
```

Buscar y descomentar (o añadir) la siguiente línea para activar el reenvío en IPv4:

```ini
net.ipv4.ip_forward = 1
```

> (Opcional) Si en el futuro se utiliza IPv6, se debería activar también en el mismo fichero mediante la siguiente entrada `net.ipv6.conf.all.forwarding = 1`.

Aplicar los cambios inmediatamente sin reiniciar:

```bash
sudo sysctl -p
```

> **⚠️ IMPORTANTE**: Reiniciar la Raspberry Pi 4 (`sudo reboot`). Esto es fundamental para que el motor de Docker (Docker Engine) detecte el cambio del sistema y configure correctamente sus reglas internas de `iptables`.

## Instrucciones de despliegue

Preparar el entorno copiando el archivo `compose.yaml` y el archivo de ejemplo para las variables de entorno `.env` y levantar el contenedor en segundo plano:

```bash
docker compose up -d
```

Comprobar los logs en tiempo real para obtener el enlace de autenticación:

```bash
docker compose logs -f tailscale
```

Buscar una línea similar a esta en la consola:

```text
To authenticate, visit: [https://login.tailscale.com/a/xxxxxxxxxxxxx](https://login.tailscale.com/a/xxxxxxxxxxxxx)
```

Copiar la URL, abrirla en un navegador web e iniciar sesión con la cuenta de Tailscale.

## Configuración post-instalación (Panel web de Tailscale)

Una vez el contenedor se haya autenticado correctamente, acceder a la [Admin Console de Tailscale](https://login.tailscale.com/admin/machines):

1. **Verificación**: Comprobar que el nuevo dispositivo aparece en la lista con el nombre configurado (`rpi4`).
2. **Desactivar Expiración**: Hacer clic en los tres puntos del dispositivo, ir a *Machine settings* y seleccionar **Disable key expiration** para evitar que el contenedor se desconecte automáticamente cada 6 meses.
3. **Aprobar Características (Routing)**: En la configuración del nodo (*Edit route settings*):
    * Activar el *checkbox* de la subred local para autorizar el enrutamiento.
    * Activar la casilla **Use as exit node** para que el resto de la red pueda navegar a través de él.

## Referencias y recursos

* [Documentación oficial: Tailscale con Docker](https://tailscale.com/kb/1282/docker)
* [Guía: Configurar Subnet Routers](https://tailscale.com/kb/1019/subnets)
* [Guía: Configurar Exit Nodes](https://tailscale.com/kb/1103/exit-nodes)
* [Historial de cambios del cliente de Tailscale](https://tailscale.com/changelog#client)
* [Videotutorial: Get started with Docker and Tailscale](https://www.youtube.com/watch?v=YTjYXii4WzI)
