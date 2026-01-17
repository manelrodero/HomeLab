# Proxmox

Mi servidor [**Proxmox Virtual Environment**](https://www.manelrodero.com/blog/proxmox-ve-802-en-un-dell-optiplex-7050) se ejecuta en un [**Dell OptiPlex 7050 Micro**](https://www.manelrodero.com/blog/mini-pc-dell-optiplex-7050-micro) que compré de segunda mano.

## Actualizaciones del SO de Proxmox

```bash
# Obtener la versión del pve-manager y del kernel
# pve-manager/8.4.14/b502d23c55afcba1 (running kernel: 6.8.12-17-pve)
pveversion

# Actualizar los repositorios de Proxmox
pveupdate

# Actualizar los paquetes de Proxmox
echo y | pveupgrade

# Reiniciar el servidor (sobretodo si hay nuevo kernel)
reboot -h now

# Obtener de nuevo la versión del pve-manager y del kernel
# pve-manager/8.4.16/368e3c45c15b895c (running kernel: 6.8.12-18-pve)
pveversion

# Limpieza de paquetes obsoletos después de reiniciar correctamente
apt autoremove -y
```

## Plantillas de SO para LXC

```bash
# Actualizar la Container Template Database
pveam update

# Listar plantillas descargadas
pveam list local

# Listar plantillas disponibles para descargar
pveam available
pveam available --section turnkeylinux  | grep -i "core"
pveam available --section system | grep -i "standard"

# Descargar plantillas para LXC
pveam download local ubuntu-24.10-standard_24.10-1_amd64.tar.zst
pveam download local debian-13-standard_13.1-2_amd64.tar.zst

# Borrar plantillas obsoletas
pveam remove local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz
pveam remove local:vztmpl/ebian-12-standard_12.12-1_amd64.tar.zst
```

## Plantilla base de contenedor LXC

El siguiente procedimiento permite crear una plantilla base de LXC (sistema operativo + configuración) que después se clonará para crear nuevos contenedores LXC ya configurados.

> Antes de seguir este procedimiento es necesario crear el fichero `proxmox.env` con las variables necesarias para nuestro entorno. Se puede utilizar como ejemplo el contenido del fichero [`proxmox.env.example`](./scripts/proxmox.env.example).

### Creación del contenedor LXC

```bash
# Acceder al directorio de scripts
cd scripts

# Crear el contenedor LXC que servirá como plantilla
bash 1-create_base_template.sh
```

La ejecución del script [`1-create_base_template.sh`](./scripts/1-create_base_template.sh) utilizará la configuración definida en el fichero `proxmox.env` y las respuestas introducidas manualmente para los siguientes parámetros:

* Nombre de la plantilla
* Identificador del contenedor LXC
* Contraseña del usuario _root_
* Dirección IP del contenedor LXC

A continuación se puede ver un ejemplo de ejecución:

```plaintext
Introduce el nombre de la plantilla:
> debian-13-lxc
Introduce el CT ID:
> 900
Introduce el password de 'root' (mínimo 5 caracteres):
> 
Confirma el password de 'root':
> 
Introduce el último octeto de la IP (10.10.0.x):
> 200
Creando el contenedor 900...
  Logical volume "vm-900-disk-0" created.
Creating filesystem with 524288 4k blocks and 131072 inodes
Filesystem UUID: fd062b30-xxxx-xxxx-xxxx-e0aa4d654290
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912
extracting archive '/var/lib/vz/template/cache/debian-13-standard_13.1-2_amd64.tar.zst'
Total bytes read: 551505920 (526MiB, 310MiB/s)
Creating SSH host key 'ssh_host_ecdsa_key' - this may take some time ...
done: SHA256:3XNyBYem4U5R3yxxxxxxxxxxxxxxx9DysRHdPYGuaas root@debian-13-lxc
Creating SSH host key 'ssh_host_rsa_key' - this may take some time ...
done: SHA256:fiqPkJ0Skvrd3uxxxxxxxxxxxxxxxvIz1jDniR/tUgM root@debian-13-lxc
Creating SSH host key 'ssh_host_ed25519_key' - this may take some time ...
done: SHA256:1Xn4y1CGdl+0CUxxxxxxxxxxxxxxx7zehqqiqWf0qz0 root@debian-13-lxc
```

### Configuración del contenedor LXC

El contenedor LXC creado anteriormente se configura mediante la ejecución del script [`2-config_base_template.sh`](./scripts/2-config_base_template.sh) dentro del mismo.

Para ello es necesario poner en marcha el contenedor mediante su identificador y utilizar los comandos `pct push` y `pct exec` para copiar y ejecutar el script.

```bash
# Poner en marcha el contenedor LXC con identificador <id>
ct_id=<id>
pct start $ct_id

# Copiar y ejecutar el fichero de configuración personalizado
pct push $ct_id ./2-config_base_template.sh /root/config_base_template.sh
pct exec $ct_id -- chmod +x /root/config_base_template.sh
pct exec $ct_id -- /root/config_base_template.sh
```

Este script:

* Configura los `locale` en-US y es-ES
* Configura la zona horaria Europe/Madrid
* Define los colores del PROMPT y el comando grep
* Define un logout por inactividad
* Instala Docker
* Crea un usuario sin privilegios (p.ej. `test`)
* (Opcional) Se le copian las `authorized_keys` si existen
* Instala el script `backup_dockers.sh` en el usuario anterior
* Programa la ejecución del script anterior de madrugada
* Instala y configura `rsync`
* Instala y configura `sudo`
* Instala y configura `unattended-upgrades`
* Instala `htop` y `net-tools`
* Borra las claves SSH obsoletas DSA y EDCSA
* Regenera las claves SSH modernas ED25519 y RSA de 3072 bits
* Configura el servidor SSH para usar las claves modernas
* Elimina paquetes obsoletos
* Borra el historial de comandos

### Convertir en plantilla de contenedor LXC

Finalmente, se puede convertir el contenedor LXC ya configurado en una **plantilla** para usarla a la hora de crear otros contenedores LXC.

Para ello es necesario parar el contenedor mediante su identificador y utilizar el comando `pct template` para crearla.

```bash
# Borrar el script de configuración
pct exec $ct_id -- rm /root/config_base_template.sh

# Parar el contenedor LXC y convertirlo en plantilla
pct stop $ct_id
pct template $ct_id
unset ct_id
```

## Clonación de la plantilla base de contenedor LXC

Se pueden crear nuevos contenedores LXC de forma rápida clonando la plantilla base de contenedor LXC creada anteriormente.

```bash
# Acceder al directorio de scripts
cd scripts

# Clonar la plantila base en un nuevo contenedor LXC
bash 3-clone_base_template.sh
```

A continuación se puede ver un ejemplo de ejecución:

```plaintext
Introduce el nombre del nuevo contenedor:
> new-lxc
Introduce el CT ID de la plantilla:
> 900
Introduce el CT ID del nuevo contenedor:
> 100
Clonando la plantilla...
create full clone of mountpoint rootfs (local-lvm:base-900-disk-0)
  Logical volume "vm-100-disk-0" created.
Creating filesystem with 524288 4k blocks and 131072 inodes
Filesystem UUID: 0f18d150-xxxx-xxxx-xxxx-feff58f8ab58
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912

Number of files: 26,272 (reg: 20,525, dir: 2,274, link: 3,449, special: 24)
Number of created files: 26,270 (reg: 20,525, dir: 2,272, link: 3,449, special: 24)
Number of deleted files: 0
Number of regular files transferred: 20,520
Total file size: 1,147,337,291 bytes
Total transferred file size: 1,142,951,332 bytes
Literal data: 1,142,951,332 bytes
Matched data: 0 bytes
File list size: 1,048,478
File list generation time: 0.001 seconds
File list transfer time: 0.000 seconds
Total bytes sent: 1,144,806,476
Total bytes received: 414,189

sent 1,144,806,476 bytes  received 414,189 bytes  176,187,794.62 bytes/sec
total size is 1,147,337,291  speedup is 1.00
RSYNC desactivado (BACKUP_RSYNC != S).
Introduce el último octeto de la IP (10.10.0.x):
> 100
Configurando red...
Introduce el número de cores (ej: 2):
> 2
Introduce la memoria RAM en MB (ej: 1024):
> 1024
Introduce la SWAP en MB (ej: 512):
> 512
Aplicando configuración de hardware...
Tamaño actual del disco de 100: 2G
Introduce el nuevo tamaño del disco en GB (>= 2):
> 2
El tamaño es igual al actual. No se realiza resize.
arch: amd64
cores: 2
features: nesting=1,keyctl=1
hostname: new-lxc
memory: 1024
net0: name=eth0,bridge=vmbr0,gw=10.10.0.1,hwaddr=BC:XX:XX:XX:XX:EB,ip=10.10.0.100/24,type=veth
onboot: 1
ostype: debian
rootfs: local-lvm:vm-100-disk-0,size=2G
swap: 512
unprivileged: 1
Contenedor 100 creado y configurado correctamente.
```

Una vez creado el contenedor, si todo ha funcionado correctamente, podremos conectarnos mediante SSH tal como se muestra a continuación:

```plaintext
C:\Users\Test> ssh test@10.10.0.100
The authenticity of host '10.10.0.100 (10.10.0.100)' can't be established.
ED25519 key fingerprint is SHA256:LL/iSuF5zsxxxxxxxxxxxxxxx/wsn2+cDDgRjx9pekU.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '10.10.0.100' (ED25519) to the list of known hosts.
Linux new-lxc 6.8.12-18-pve #1 SMP PREEMPT_DYNAMIC PMX 6.8.12-18 (2025-12-15T18:07Z) x86_64

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
test@new-lxc:~$
```

## (Opcional) Añadir Mount Point para RSync

Opcionalmente se puede añadir un Mount Point al contenedor LXC para que el script [`backup_dockers.sh`](./scripts/backup_dockers.sh) lo use como destino de las **copias de seguridad** de los contenedores Docker que se ejecuten en ese LXC.

Para hacerlo, se ejecuta el script [`add_rsync_lxc.sh`](./scripts/add_rsync_lxc.sh) de la siguiente manera:

```bash
# Acceder al directorio de scripts
cd scripts

# Añadir Mount Point al LXC
bash add_rsync_lxc.sh
```

Un ejemplo de ejecución se muestra a continuación:

```plaintext
Introduce el ID del contenedor LXC:
> 100
Directorio creado: /backups/rsync/100-new-lxc
Configuración completada para el contenedor 100 (new-lxc).
Se ha añadido el punto de montaje en mp0 → /mnt/rsync
```

El punto de montaje añadido se puede ver en la interfaz gráfica de Proxmox (**Datacenter** &rarr; **Servidor** &rarr; **Contenedor LXC** &rarr; **Resources**).

Tambíen se puede realizar un `cat` del fichero de configuración del contenedor LXC tal como se muestra en el siguiente ejemplo:

```plaintext
root@pve:~/HomeLab/Proxmox/scripts# cat /etc/pve/lxc/100.conf
arch: amd64
cores: 2
features: nesting=1,keyctl=1
hostname: new-lxc
memory: 1024
mp0: /backups/rsync/100-new-lxc,mp=/mnt/rsync
net0: name=eth0,bridge=vmbr0,gw=10.10.0.1,hwaddr=BC:XX:XX:XX:XX:EB,ip=10.10.0.100/24,type=veth
onboot: 1
ostype: debian
rootfs: local-lvm:vm-100-disk-0,size=2G
swap: 512
unprivileged: 1
```
