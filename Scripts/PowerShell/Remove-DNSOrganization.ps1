# ================================================================================
# Script   : Remove-DNSOrganization.ps1
# Autor    : Manel Rodero
# Fecha    : 2022-11-03
# Versión  : 1.2
# Problema : FortiClient añade los servidores DNS de la Organización a cualquier interfaz
#            del equipo: Ethernet, Fortinet, Hyper-V, etc.
#            Esto hace que cualquier consulta DNS (p.ej. al navegar, nslookup, etc.)
#            se realice a los servidores de la Organización lo cual hace que todo vaya más
#            lento debido a la latencia que tienen para contestar respecto al
#            servidor DNS del equipo en casa (Pi-Hole, AdGuard Home, QuadDNS, etc.)
# Solución : Revisar todas las interfaces y eliminar el DNS de la Organización para dejar
#            únicamente el que tuviese configurado el equipo.
#            Inicialmente se pensó que no había que quitarlos de la interfaz de
#            Fortinet pero es necesario para que vuelva a usarse el original.
#            No es necesario reiniciar las interfaces (de hecho, si se reinician
#            la conexión VPN cae y, obviamente, desaparece el problema)
# ================================================================================

$DNS = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {($_.ServerAddresses -contains "10.83.0.1")}
foreach ($d in $DNS) {
   $a = Get-NetAdapter -IncludeHidden -InterfaceIndex $d.InterfaceIndex
   Write-Host "Comprobando interfaz '$($d.InterfaceAlias)':"
   Write-Host "- $($a.InterfaceDescription)"
   Write-Host "- $($d.ServerAddresses)"

# Si no se trata también esta interfaz de Fortinet, se sigue usando los DNS de la Organización debido a que tienen mayor peso
# if ($a.InterfaceDescription -ne 'Fortinet SSL VPN Virtual Ethernet Adapter') {

      # Si no es la interfaz SSL VPN, quitamos los servidores DNS de la UPC
      [System.Collections.ArrayList]$l = $d.ServerAddresses
      $l.Remove("10.83.0.1")
      $l.Remove("10.83.0.2")

      if ($l) {
         # Si ha quedado algún servidor DNS, seguramente será la interfaz Ethernet del equipo...
         Write-Host "* Configurando DNS = $l"
         $a | Set-DnsClientServerAddress -ServerAddresses $l
      } else {
         # Si no ha quedado ningún servidor DNS, se puede restaurar al valor por defecto
         Write-Host "* Reset direcciones DNS"
         $a | Set-DnsClientServerAddress -ResetServerAddresses
      }
# }
}

# Cambiar DNS Suffix Search List
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters -Name 'SearchList' -Value 'home'
