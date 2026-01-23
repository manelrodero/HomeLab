FROM ubuntu:24.04

# Dockerfile v9 - 2025-08-21, (c) Manel Rodero & NordVPN

# FRONTEND no interactivo para evitar warnings como estos a la hora de construir la imagen:
# 
# debconf: falling back to frontend: Readline
# debconf: unable to initialize frontend: Readline
# debconf: (Can't locate Term/ReadLine.pm in @INC [...]
# debconf: falling back to frontend: Teletype 

ENV DEBIAN_FRONTEND=noninteractive

# Instalación de NordVPN y sus dependencias según documentación oficial:
# https://support.nordvpn.com/hc/en-us/articles/20465811527057
#
# También se instalan algunas utilidades de red, útiles a la hora de depurar la conexión:
# +----------------+------------------------------------------------------------+-----------------------------+
# | Paquete        | Función principal                                          | Comando(s) destacado(s)     |
# +----------------+------------------------------------------------------------+-----------------------------+
# | curl           | Cliente para transferencias HTTP/HTTPS, FTP, etc.          | curl http://example.com     |
# | iputils-ping   | Herramienta para comprobar conectividad ICMP (ping)        | ping 8.8.8.8                |
# | net-tools      | Conjunto de herramientas clásicas de red (ifconfig, etc.)  | ifconfig, netstat, route    |
# | dnsutils       | Herramientas para consultas DNS (dig, nslookup)            | dig google.com, nslookup    |
# | iproute2       | Herramientas modernas para gestión de red (ip, ss, etc.)   | ip addr, ip route, ss -tuln |
# +----------------+-------------------------------------------------------------+-----------------------------+

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        curl \
        iputils-ping \
        net-tools \
        dnsutils \
        iproute2 \
        apt-transport-https \
        ca-certificates && \
    wget -qO /etc/apt/trusted.gpg.d/nordvpn_public.asc https://repo.nordvpn.com/gpg/nordvpn_public.asc && \
    echo "deb https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nordvpn && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Docker recomienda que tanto ENTRYPOINT como CMD se definan usando sintaxis JSON
# (es decir, como una lista de argumentos) en lugar de una cadena de texto.

# En la documentación oficial de NordVPN "How to build the NordVPN Docker image"
# se usan cadenas de texto y esto genera warnings como el siguiente al construir la imagen:
#
# JSONArgsRecommended: JSON arguments recommended for ENTRYPOINT
# to prevent unintended behavior related to OS signals (line 13)
#
# Usar un script mejora el manejo de señales del sistema operativo
# (como SIGTERM, SIGINT) y evita que el shell intermedio interfiera.

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD []
