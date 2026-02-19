# Configuración de Hyper-V

En casa utilizo Hyper-V como hipervisor para trabajar con máquinas virtuales.

Habitualmente las conecto al `Default Switch` que proporciona salida desde la red **interna** a Internet utilizando NAT.

La configuración del **adaptador virtual** `vEthernet (Default Switch)` suele ser algo así:

```plaintext
Ethernet adapter vEthernet (Default Switch):

   Connection-specific DNS Suffix  . :
   Description . . . . . . . . . . . : Hyper-V Virtual Ethernet Adapter
   Physical Address. . . . . . . . . : 00-15-5D-XX-XX-XX
   DHCP Enabled. . . . . . . . . . . : No
   Autoconfiguration Enabled . . . . : Yes
   Link-local IPv6 Address . . . . . : fe80::596d:a8c1:e09b:df51%28(Preferred)
   IPv4 Address. . . . . . . . . . . : 172.17.32.1(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.240.0
   Default Gateway . . . . . . . . . :
   DHCPv6 IAID . . . . . . . . . . . : 469767517
   DHCPv6 Client DUID. . . . . . . . : 00-01-00-01-29-24-34-AD-F0-2F-74-F6-51-62
   NetBIOS over Tcpip. . . . . . . . : Enabled
```

La configuración de mi **adaptador físico** `Ethernet` en esta situación es la siguiente:

```plaintext
Ethernet adapter Ethernet:

   Connection-specific DNS Suffix  . :
   Description . . . . . . . . . . . : Realtek PCIe 2.5GbE Family Controller
   Physical Address. . . . . . . . . : F0-2F-74-XX-XX-XX
   DHCP Enabled. . . . . . . . . . . : No
   Autoconfiguration Enabled . . . . : Yes
   Link-local IPv6 Address . . . . . : fe80::4c46:6fc1:3996:f53%26(Preferred)
   IPv4 Address. . . . . . . . . . . : 192.168.1.10(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1
   DHCPv6 IAID . . . . . . . . . . . : 116404084
   DHCPv6 Client DUID. . . . . . . . : 00-01-00-01-29-24-34-AD-F0-2F-74-XX-XX-XX
   DNS Servers . . . . . . . . . . . : 192.168.1.50
                                       192.168.1.80
   NetBIOS over Tcpip. . . . . . . . : Disabled
```

## Configuración External Switch

La configuración de un nuevo _switch_ **externo** de Hyper-V modifica la configuración de red de Windows:

- Name: External Switch
- Connection type: External network
  - Realtek PCIe 2.5GbE Family Controller
  - Allow management operating system to share the network adapter

Al crear el switch anterior, Windows modifica su configuración de red de la siguiente manera:

- **El adaptador Realtek se convierte en un "Bridge"**: Windows desvincula los protocolos de red (IP, DNS, etc.) de tu tarjeta física Realtek y los mueve a un nuevo adaptador virtual llamado `vEthernet (External Switch)`
- **La IP Estática se mueve**: La configuración de IP estática debería migrar automáticamente de la Realtek al adaptador virtual `vEthernet`. La tarjeta física queda "muda", funcionando solo como un cable para el switch.

Pero esta migración no siempre se produce correctamente y el adaptador virtual queda configurado de forma similar a:

```plaintext
Ethernet adapter vEthernet (External Switch):

   Connection-specific DNS Suffix  . :
   Description . . . . . . . . . . . : Hyper-V Virtual Ethernet Adapter #2
   Physical Address. . . . . . . . . : F0-2F-74-XX-XX-XX
   DHCP Enabled. . . . . . . . . . . : No
   Autoconfiguration Enabled . . . . : Yes
   Link-local IPv6 Address . . . . . : fe80::4c46:6fc1:3996:f53%54(Preferred)
   IPv4 Address. . . . . . . . . . . : 192.168.1.10(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1
   DHCPv6 IAID . . . . . . . . . . . : 921710452
   DHCPv6 Client DUID. . . . . . . . : 00-01-00-01-29-24-34-AD-F0-2F-74-XX-XX-XX
   DNS Servers . . . . . . . . . . . : fec0:0:0:ffff::1%1
                                       fec0:0:0:ffff::2%1
                                       fec0:0:0:ffff::3%1
   NetBIOS over Tcpip. . . . . . . . : Enabled
```

Se puede observar que ha heredado la MAC del adaptador físico y también su dirección IP, máscara y puerta de enlace.

Pero se han perdido los servidores DNS IPv4 y, al no tener servidores DNS válidos configurados, Windows asigna unas **direcciones IPv6 de sitio local**.

Esta situación hace que no se puedan resolver nombres DNS y sea imposible navegar o utilizar cualquier servicio _online_.

Para arreglarlo hay que ejecutar `ncpa.cpl` y cambiar la configuración del protocolo **TCP/IPv4** del adaptador `vEthernet` para:

- Añadir los servidores DNS: 192.168.1.50 y 192.168.1.80
  - La migración había indicado configuración manual sin indicar ninguno
- Desactivar el registro de la IP de la conexión en el DNS
- Deshabilitar NetBIOS sobre TCP/IP
- Deshabilitar LMHOSTS lookup

Una vez corregido, la configuración del adaptador virtual queda de la siguiente manera:

```plaintext
Ethernet adapter vEthernet (External Switch):

   Connection-specific DNS Suffix  . :
   Description . . . . . . . . . . . : Hyper-V Virtual Ethernet Adapter #2
   Physical Address. . . . . . . . . : F0-2F-74-XX-XX-XX
   DHCP Enabled. . . . . . . . . . . : No
   Autoconfiguration Enabled . . . . : Yes
   Link-local IPv6 Address . . . . . : fe80::4c46:6fc1:3996:f53%54(Preferred)
   IPv4 Address. . . . . . . . . . . : 192.168.1.10(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1
   DHCPv6 IAID . . . . . . . . . . . : 921710452
   DHCPv6 Client DUID. . . . . . . . : 00-01-00-01-29-24-34-AD-F0-2F-74-XX-XX-XX
   DNS Servers . . . . . . . . . . . : 192.168.1.50
                                       192.168.1.80
   NetBIOS over Tcpip. . . . . . . . : Disabled
```

En este instante el ordenador vuelve a tener conectividad con Internet y las máquinas virtuales obtendrán una dirección de la red `192.168.1.0/24` gracias a la configuración DHCP que utiliza Windows por defecto.

## Protocolos en los adaptadores

En esta situación, muchos de los protocolos del adaptador físico se desactivan y se activan en el adaptador virtual.

| Protocolo | Ethernet | vEthernet (External Switch) |
| --- | --- | --- |
| Cliente para redes Microsoft | | x |
| Uso compartido de archivos e impresoras para redes Microsoft | | x |
| Npcap Packet Driver (NPCAP) | | x |
| NordVPN LightWeight Firewall | | x |
| Programador de paquetes QoS | | x |
| FortiClient NDIS 6.3 Packet Filter Driver | | x |
| Controlador de puertos | | x |
| Virtualización de red anidada | x | x |
| Protocolo de Internet versión 4 (TCP/IPv4) | | x |
| Protocolo de multiplexor de adaptador de red de Microsoft (*) | | |
| Controlador de protocolo LLDP de Microsoft | x | x |
| Protocolo de Internet versión 6 (TCP/IPv6) | | x |
| Respondedor de detección de topologías de nivel de vínculo | | x |
| Controlador de E/S del asignador de detección de topologías de nivel de vínculo | | x |
| Conmutador virtual extensible de Hyper-V | x | |

> El protocolo (*) no existe en el adaptador de red físico.

## Conexión con FortiClient VPN

Cuando se conecta correctamente FortiClient VPN aparece un nuevo adaptador de red (en este caso `Ethernet 3`) con la dirección IP asignada por la organización:

```plaintext
Ethernet adapter Ethernet 3:

   Connection-specific DNS Suffix  . :
   Description . . . . . . . . . . . : Fortinet SSL VPN Virtual Ethernet Adapter
   Physical Address. . . . . . . . . : 00-09-0F-XX-XX-XX
   DHCP Enabled. . . . . . . . . . . : No
   Autoconfiguration Enabled . . . . : Yes
   Link-local IPv6 Address . . . . . : fe80::2f51:fa6:3115:2490%23(Preferred)
   IPv4 Address. . . . . . . . . . . : 10.6.X.X(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.255.255
   Default Gateway . . . . . . . . . :
   DHCPv6 IAID . . . . . . . . . . . : 671090959
   DHCPv6 Client DUID. . . . . . . . : 00-01-00-01-29-24-34-AD-F0-2F-74-XX-XX-XX
   NetBIOS over Tcpip. . . . . . . . : Enabled
```

Además se producen algunos cambios en la configuración de red del ordenador tales como:

- Se modifica la **DNS Suffix Search List** para insertar al principio de la lista los dominios de la organización

```plaintext
   DNS Suffix Search List. . . . . . : domain.org
                                       home
```

- Se modifican los **DNS Servers** del adaptador `vEthernet (External Switch)` para insertar al principio de la lista los servidores DNS de la organización

```plaintext
   DNS Servers . . . . . . . . . . . : 10.83.0.1
                                       10.83.0.2
                                       192.168.1.50
                                       192.168.1.80
```

- Se modifican los **DNS Servers** del adaptador `vEthernet (Default Switch)` para insertar al principio de la lista los servidores DNS de la organización

```plaintext
   DNS Servers . . . . . . . . . . . : 10.83.0.1
                                       10.83.0.2
```

- Se modifica la **tabla de rutas** para indicar las redes de la organización que serán accessibles a través de la interfaz

> En mi caso, después de conectar con la VPN, siempre ejecuto un _script_ [`Remove-DNSOrganization.ps1`](../Scripts/Remove-DNSOrganization.ps1) que elimina los servidores DNS de la organización de cualquier interfaz. De esta manera puedo seguir usando mis servidores DNS locales.
