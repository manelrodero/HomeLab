#!/bin/bash

# Create base for LXC Template v1.9 (2026-01-16)

set -e

echo "🔄 Configurando 'locale'..."
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^# *\(es_ES.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
cat <<EOF > /etc/default/locale
LANG=en_US.UTF-8
LANGUAGE=en_US:en
LC_CTYPE=es_ES.UTF-8
EOF

echo "🔄 Configurando zona horaria..."
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
echo "Europe/Madrid" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

echo "🔄 Forzando colores en PROMPT y grep..."
sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc
sed -i -E "s/^([[:space:]]*)#([[:space:]]*)alias grep='grep --color=auto'/\1\2alias grep='grep --color=auto'/" /etc/skel/.bashrc

echo "🔄 Aplicando colores al usuario 'root'..."
cp ~/.bashrc ~/.bashrc.bak
cp ~/.profile ~/.profile.bak
cp /etc/skel/.bashrc ~/.bashrc
cp /etc/skel/.profile ~/.profile

echo "🔄 Configurando Logout por inactividad (30 min)..."
cat <<EOF >> /etc/bash.bashrc

# Logout por inactividad (30 min)
export TMOUT=1800
readonly TMOUT
EOF

echo "🔄 Aceptando metadatos del repositorio..."
apt update --allow-releaseinfo-change

echo "🔄 Instalando clave GPG de Docker..."
apt install ca-certificates curl -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "🔄 Añadiendo el repositorio de Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update

echo "🔄 Instalando Docker Engine..."
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${GREEN}Introduce el nombre del usuario sin privilegios:${NC}"
read -p "> " user

echo -e "${CYAN}Creando el usuario '${user}'...${NC}"
useradd -m -u 1000 -U -G docker -s /bin/bash "$user"

echo -e "${CYAN}Estableciendo contraseña para '${user}'...${NC}"
passwd "$user"

cat /etc/passwd | grep -i "$user"
cat /etc/group | grep -i "$user"

if [ -f "$HOME/.ssh/authorized_keys" ]; then
    echo "🔄 Copiando 'authorized_keys' al usuario '$user'..."
    mkdir -p "/home/$user/.ssh"
    cp "$HOME/.ssh/authorized_keys" "/home/$user/.ssh/"
    chown -R "$user:$user" "/home/$user/.ssh"
else
    echo "ℹ️  No existe '$HOME/.ssh/authorized_keys'. Se omite la copia."
fi

echo "🔄 Descargando fichero 'backup_dockers.sh'..."
mkdir -p "/home/$user/dockers"
curl -fsSL \
  https://raw.githubusercontent.com/manelrodero/HomeLab/refs/heads/main/Proxmox/scripts/backup_dockers.sh \
  -o "/home/$user/dockers/backup_dockers.sh"

chmod +x "/home/$user/dockers/backup_dockers.sh"
chown -R "$user:$user" "/home/$user/dockers"

echo "🔄 Programando ejecución de 'backup_dockers.sh'..."
echo "# m h  dom mon dow   command" > "/tmp/${user}_cron"
echo "00 2 * * * /home/$user/dockers/backup_dockers.sh >/dev/null 2>&1" >> "/tmp/${user}_cron"
crontab -u "$user" "/tmp/${user}_cron"
crontab -u "$user" -l
rm "/tmp/${user}_cron"

echo "🔄 Instalando y configurando 'rsync'..."
mkdir -p /mnt/rsync
chown root:"$user" /mnt/rsync
chmod 770 /mnt/rsync
apt install rsync -y

echo "🔄 Instalando y configurando 'sudo'..."
apt install sudo -y
echo "# Configuración Sudo para $user" > "/etc/sudoers.d/$user"
echo "$user ALL=(ALL) NOPASSWD: /usr/bin/rsync" >> "/etc/sudoers.d/$user"
echo "$user ALL=(ALL) NOPASSWD: /usr/bin/nano" >> "/etc/sudoers.d/$user"
echo "$user ALL=(ALL) NOPASSWD: /usr/bin/rm" >> "/etc/sudoers.d/$user"
echo "$user ALL=(ALL) NOPASSWD: /usr/bin/ls" >> "/etc/sudoers.d/$user"
echo "$user ALL=(ALL) NOPASSWD: /usr/sbin/reboot" >> "/etc/sudoers.d/$user"
echo "$user ALL=(ALL) NOPASSWD: /usr/sbin/shutdown" >> "/etc/sudoers.d/$user"
chmod 0440 "/etc/sudoers.d/$user"
visudo -cf "/etc/sudoers.d/$user"

echo "🔄 Instalando y configurando 'unattended-upgrades'..."
apt install -y unattended-upgrades apt-listchanges
sed -i -E 's|^([[:space:]]*)//([[:space:]]*)"origin=Debian,codename=\$\{distro_codename\}-updates";|\1  \2"origin=Debian,codename=${distro_codename}-updates";|' /etc/apt/apt.conf.d/50unattended-upgrades

echo "🔄 Ejecutando 'unattended-upgrades'..."
unattended-upgrades -d

echo "🔄 Ejecutando 'apt update'..."
apt update

echo "🔄 Instalando 'htop' y 'net-tools'..."
apt install htop -y
apt install net-tools -y

echo "🔐 Eliminando claves antiguas DSA y ECDSA si existen..."
rm -f /etc/ssh/ssh_host_dsa_key*
rm -f /etc/ssh/ssh_host_ecdsa_key*

echo "🔑 Regenerando clave ED25519..."
yes | ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

echo "🔑 Regenerando clave RSA (3072 bits)..."
yes | ssh-keygen -t rsa -b 3072 -f /etc/ssh/ssh_host_rsa_key -N ""

echo "🔄 Configurando servidor SSH..."
CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.bak"

# Crear copia de seguridad
cp "$CONFIG" "$BACKUP"

# Procesar el archivo
awk '
BEGIN { found_pubkey = 0 }
{
    if ($0 ~ /^[# ]*HostKey[ \t]+\/etc\/ssh\/ssh_host_rsa_key/) {
        print "HostKey /etc/ssh/ssh_host_rsa_key"
    } else if ($0 ~ /^[# ]*HostKey[ \t]+\/etc\/ssh\/ssh_host_ed25519_key/) {
        print "HostKey /etc/ssh/ssh_host_ed25519_key"
    } else if ($0 ~ /^[^#]*HostKey[ \t]+\/etc\/ssh\/ssh_host_dsa_key/) {
        print "#" $0
    } else if ($0 ~ /^[^#]*HostKey[ \t]+\/etc\/ssh\/ssh_host_ecdsa_key/) {
        print "#" $0
    } else if ($0 ~ /^PubkeyAcceptedKeyTypes/) {
        print "PubkeyAcceptedKeyTypes ssh-ed25519,ssh-rsa"
        found_pubkey = 1
    } else {
        print $0
    }
}
END {
    if (found_pubkey == 0) {
        print ""
        print "PubkeyAcceptedKeyTypes ssh-ed25519,ssh-rsa"
    }
}
' "$BACKUP" > "$CONFIG"

echo "🔄 Reiniciando servidor SSH..."
systemctl restart ssh

echo "🔄 Eliminando paquetes innecesarios..."
apt autoremove -y
apt autoclean -y

echo "🔄 Borrando historial..."
history -c
unset HISTFILE
rm -f ~/.bash_history

exit
