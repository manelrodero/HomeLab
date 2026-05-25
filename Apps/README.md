# Aplicaciones de HomeLab

Este directorio centraliza la configuración de los diferentes servicios y aplicaciones que se ejecutan en mi infraestructura local.

La mayoría de los despliegues están basados en contenedores Docker para garantizar la portabilidad y facilitar el mantenimiento.

## Índice de servicios

| Aplicación | Servidor / Host | Tecnología | Descripción |
| :--- | :--- | :--- | :--- |
| [NordVPN](./nordvpn/README.md) | Proxmox | Docker / LXC | Cliente VPN para asegurar el tráfico de contenedores específicos |
| [Tailscale](./tailscale/README.md) | Raspberry Pi 4 | Docker (Host) | VPN Mesh con funciones de Subnet Router y Exit Node. |

## Estructura del repositorio

Cada subdirectorio contiene los artefactos necesarios para el despliegue del servicio:

* `compose.yaml`: Declaración del stack de Docker.
* `.env.sample`: Plantilla de variables de entorno requeridas (opcional).
* `update.sh`: Script personalizado para la automatización de copias de seguridad previas y actualizaciones de la imagen Docker (opcional).
* `README.md`: Documentación específica de prerrequisitos, despliegue y post-configuración.
