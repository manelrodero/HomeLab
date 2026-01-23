# NordVPN

NordVPN es un **servicio de red privada virtual (VPN)** diseñado para proporcionar una conexión a internet **más segura, privada y protegida**.

Según diferentes análisis, se lo describe como uno de los servicios VPN más rápidos y avanzados del mercado, con miles de servidores en más de 178 ubicaciones.

## ¿Qué hace exactamente NordVPN?

- **Cifra la conexión a internet**, de modo que nadie pueda ver lo que se hace online (ni el proveedor, ni redes Wi‑Fi públicas, ni posibles atacantes).  
- **Oculta la dirección IP**, permitiendo navegar con más privacidad y evitar rastreadores o vigilancia no deseada.  
- **Protege contra malware, phishing y anuncios maliciosos** mediante su función Threat Protection Pro™.  
- **Permite acceder a contenido global**, conectándose a servidores de otros países para evitar bloqueos geográficos.  
- **Ofrece miles de servidores** (más de 8900 en 178+ localizaciones) para asegurar velocidad y estabilidad.

## Funciones destacadas

- **NordLynx**, su protocolo propio, optimizado para velocidad y seguridad.  
- **Doble VPN**, que cifra la conexión dos veces para mayor privacidad.  
- **Servidores ofuscados**, útiles en países con restricciones fuertes.  
- **Dark Web Monitor**, que avisa si tus datos aparecen filtrados online.  
- **Protección en hasta 10 dispositivos** con una sola cuenta.

## NordVPN Custom

Cuando [instalé qBittorrent en un contenedor LXC](https://www.manelrodero.com/blog/instalar-qbittorrent-en-proxmox-lxc) en noviembre de 2023 no lo enrutaba a través de una VPN lo cual podía ser un problema a la hora de [descargar una ISO de Ubuntu](https://ubuntu.com/download/alternative-downloads#bit-torrent).

En marzo de 2025 [instalé NordVPN en el contenedor LXC](https://www.manelrodero.com/blog/usar-nordvpn-con-qbittorrent-en-proxmox-lxc) para enrutar el tráfico BitTorrent a través de la VPN. Esta primera instalación de NordVPN se realizó directamente en el propio _host_.

En agosto de 2025 cambié la instalación de **NordVPN** y **qBittorrent** a contenedores **Docker** ejecutándose dentro de un **contenedor LXC** de mi servidor Proxmox.

Esto se hizo construyendo una **imagen _custom_** de NordVPN tal como explican en su artículo [How to build the NordVPN Docker image]( https://support.nordvpn.com/hc/en-us/articles/20465811527057).

Los ficheros necesarios para construir la imagen personalizada **nordvpn-custom** son los siguientes:

- [`rebuild.sh`](./rebuild.sh), script que reconstruye la imagen
- [`./nordvpn-custom/Dockerfile`](./nordvpn-custom/Dockerfile), Dockerfile de la imagen personalizada
- [`./nordvpn-custom/entrypoint.sh`](./nordvpn-custom/entrypoint.sh), script de inicialización de la imagen

## Docker

A partir de esta imagen personalizada se puede construir un _stack_ Docker que incluya la VPN, un cliente de BitTorrent y cualquier otro programa que se quiera ejecutar a través de la misma red.

Algunos detalles a tener en cuenta sobre el fichero [`compose.yaml`](compose.yaml) de este _stack_ son los siguientes:

- Algunas variables locales o sensibles, como el **token** de NordVPN, se configuran en el fichero `.env` (se puede renombrar y modificar el fichero [`.env.example`](.env.example) según el entorno).
- Es necesario previamente crear una red de tipo _bridge_ que se llame **vpntorrent**.
- Los directorios de _media_ y _torrent_ de los Docker se montan sobre el mismo directorio base `/mnt/media` para facilitar el movimiento de los ficheros de un programa a otro.

Se puede poner en marcha el _stack_ mediante el comando:

```bash
docker compose up -d
```

Se pueden ver los logs mediante el comando:

```bash
docker compose logs -f
```

Se puede para el _stack_ mediante el comando:

```bash
docker compose down
```

## Comprobación de la VPN

Para comprobar que la VPN funciona correctamente se puede ejecutar el comando `nordvpn status` dentro del contenedor **nordvpn** de la siguiente manera:

```bash
docker exec -it nordvpn nordvpn status
```

```plaintext
Status: Connected
Server: Spain #243
Hostname: es243.nordvpn.com
IP: 185.xxx.xxx.146
Country: Spain
City: Barcelona
Current technology: NORDLYNX
Current protocol: UDP
Post-quantum VPN: Disabled
Transfer: 7.75 MiB received, 483.62 KiB sent
Uptime: 2 minutes 49 seconds
```

De forma similar, también se puede ejecutar el comando `wget` para obtener la dirección IP pública mediante un servicio externo que la proporcione:

```bash
docker exec -it nordvpn wget -qO- https://ipinfo.io
```

```plaintext
{
  "ip": "185.xxx.xxx.253",
  "city": "Barcelona",
  "region": "Catalonia",
  "country": "ES",
  "loc": "41.3888,2.1590",
  "org": "AS207137 PacketHub S.A.",
  "postal": "08007",
  "timezone": "Europe/Madrid",
  "readme": "https://ipinfo.io/missingauth"
```

La dirección IP debería ser diferente de la obtenida desde fuera del contenedor, que será la proporcionada por nuestro ISP.

Por ejemplo, en el caso de Orange desde Barcelona podría ser algo así:

```bash
wget -qO- https://ipinfo.io
```

```plaintext
{
  "ip": "92.xxx.xxx.xxx",
  "hostname": "xx.pool92-xxx-xxx.dynamic.orange.es",
  "city": "Almería",
  "region": "Andalusia",
  "country": "ES",
  "loc": "36.8381,-2.4597",
  "org": "AS12479 Orange Espagne SA",
  "postal": "04001",
  "timezone": "Europe/Madrid",
  "readme": "https://ipinfo.io/missingauth"
```

> La localización GPS, la ciudad o la región proporcionadas por estos servicios podría no ser la real ya que dependen de tener actualizada su base de datos de redes y proveedores.

```bash
wget -qO- https://ipv4.ipleak.net/json/
```

```plaintext
{
    "as_number": 12479,
    "isp_name": "Orange Espagne SA",
    "country_code": "ES",
    "country_name": "Spain",
    "region_code": "B",
    "region_name": "Barcelona",
    "continent_code": "EU",
    "continent_name": "Europe",
    "city_name": "xxxxx",
    "postal_code": null,
    "postal_confidence": null,
    "latitude": xxxxx,
    "longitude": xxxxx,
    "accuracy_radius": 5,
    "time_zone": "Europe\/Madrid",
    "metro_code": null,
    "level": "min",
    "cache": 1769190947,
    "ip": "92.xxx.xxx.xxx",
    "reverse": "",
    "query_text": "92.xxx.xxx.xxx",
    "query_type": "myip",
    "query_date": 1769190947
```

Para comprobar que otro contenedor Docker puede utilizar la conexión de red proporcionada por **nordvpn-custom**, se puede utilizar una imagen básica de Alpine:

```bash
docker run --rm --network=container:nordvpn alpine:3.20 sh -c "apk add wget && wget -qO- https://ipinfo.io"
```

```plaintext
fetch https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/APKINDEX.tar.gz
fetch https://dl-cdn.alpinelinux.org/alpine/v3.20/community/x86_64/APKINDEX.tar.gz
(1/4) Installing libunistring (1.2-r0)
(2/4) Installing libidn2 (2.3.7-r0)
(3/4) Installing pcre2 (10.43-r0)
(4/4) Installing wget (1.24.5-r0)
Executing busybox-1.36.1-r30.trigger
OK: 11 MiB in 18 packages
{
  "ip": "185.xxx.xxx.253",
  "city": "Barcelona",
  "region": "Catalonia",
  "country": "ES",
  "loc": "41.3888,2.1590",
  "org": "AS207137 PacketHub S.A.",
  "postal": "08007",
  "timezone": "Europe/Madrid",
  "readme": "https://ipinfo.io/missingauth"
```
