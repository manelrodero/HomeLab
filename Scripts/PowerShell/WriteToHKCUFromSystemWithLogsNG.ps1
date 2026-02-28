# Fitxer UTF-8 with BOM per escriure accents i caràcters especials

# Writing Current User registry keys in SCCM as System
# https://tdemeul.bunnybesties.org/2022/04/writing-current-user-registry-keys-in.html

# Modificado 27/06/2022 para UPC (Entorno GET)
# Modificado 16/07/2025 para UPC (Entorno mGET)
# Modificado 28/02/2026 para UPC (Entorno mGET) - HKEY_USERS <> TOTS els usuaris (només carregats per inici de sessió)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\.reg$')]
    [string]$RegFile,

    [switch]$CurrentUser,
    [switch]$AllUsers,
    [switch]$DefaultProfile
)

# ---------------------------------------------------------------------------
# FUNCIONS DE SUPORT (HELPER FUNCTIONS)
# ---------------------------------------------------------------------------

# Escriure logs en format text pla o CMTrace, gestionant automàticament les rutes de log segons l'entorn
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [bool]$Output = $false,

        [Parameter(Mandatory = $false)]
        [bool]$OriginalOutput = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info",

        [Parameter(Mandatory = $false)]
        [string]$Component = $(Split-Path -Leaf $MyInvocation.PSCommandPath).Replace('.ps1', ''),

        [Parameter(Mandatory = $false)]
        [string]$LogName = $(Split-Path -Leaf $MyInvocation.PSCommandPath).Replace('.ps1', ''),

        [Parameter(Mandatory = $false)]
        [switch]$UseCMTrace,

        [Parameter(Mandatory = $false)]
        [bool]$InitFile = $false
    )

    if ($UseCMTrace) {
        # Format CMTrace
        $typeMap = @{ "Info" = "1"; "Warning" = "2"; "Error" = "3" }
        $timestamp = Get-Date
        $logEntry = "<![LOG[$Message]LOG]!><time=""{0}"" date=""{1}"" component=""{2}"" context=""{3}"" type=""{4}"" thread="""" file="""">" -f `
            $timestamp.ToString("HH:mm:ss.ffffff"), $timestamp.ToString("M-d-yyyy"), $Component, $env:USERNAME, $typeMap[$Level]
    } else {
        # Format text pla amb timestamp
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "$timestamp [$Level] $Component :: $Message"
    }

    # Determinar ruta del log si no s'ha especificat
    # 1) Intune: $env:ProgramData\Microsoft\IntuneManagementExtension\Logs
    # 2) Subdirectori del script: $PSScriptRoot\Logs
    # 3) $env:TEMP\Logs
    # 4) $env:TEMP
    $LogPaths = @(
        "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",
        "$PSScriptRoot\Logs",
        "$env:TEMP\Logs",
        "$env:TEMP"
    )

    foreach ($path in $LogPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        try {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            $FullFile = Join-Path $path "UPC-$LogName.log"

            if ($InitFile) {
                $logEntry | Out-File -FilePath $FullFile -Encoding utf8 -Force -ErrorAction Stop
            } else {
                $logEntry | Out-File -FilePath $FullFile -Append -Encoding utf8 -ErrorAction Stop
            }

            break
        } catch {
            continue
        }
    }

    if ($Output) {
        if ($OriginalOutput) {
            Write-Output $Message
        } else {
            Write-Output $logEntry
        }
    }
}

# Variables de cache per evitar repeticions de consultes
$script:CachedLoggedOnSID = $null
$script:CheckedLoggedOnSID = $false

# Consultar el registre (ProfileList) per convertir un SID d'usuari en la ruta física del seu perfil (p.ex. C:\Users\nom.usuari)
function Get-ProfilePathFromSID($sid) {
    try {
        $path = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid").ProfileImagePath
        return $path
    } catch {
        return $null
    }
}

# Extreu el nom de la carpeta de l'usuari (un nom curt de fins a 20 caràcters) a partir del seu SID
function Get-UsernameFromSID($sid) {
    $path = Get-ProfilePathFromSID $sid
    if ($path) { return (Split-Path $path -Leaf) }
    return $null
}

# Detecta qui és l'usuari que té la sessió iniciada actualmment buscant el propietari del procés explorer.exe
# En un entorn multiu-usuari podria haver-hi més d'un usuari (encara que només un estigui fent servir la consola/escriptori)
# Inclou memòria cau (cache) per no repetir la consulta
function Get-LoggedOnUserSID {

    # Si ja tenim una llista de SIDs vàlids cachejada → retornar-la
    if ($script:CheckedLoggedOnSID -and $script:CachedLoggedOnSID) {
        return $script:CachedLoggedOnSID
    }

    $FoundSIDs = @()

    # Buscar usuaris interactius
    try {
        # Fem servir Get-CimInstance (més modern i ràpid que WMI) per trobar TOT els explorer.exe
        $explorers = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'"

        foreach ($proc in $explorers) {
            # Obtenim el propietari del procés mitjançant Invoke-CimMethod
            $owner = Invoke-CimMethod -InputObject $proc -MethodName "GetOwner"

            if ($owner.ReturnValue -eq 0) {
                try {
                    $acct = New-Object System.Security.Principal.NTAccount("$($owner.Domain)\$($owner.User)")
                    $sid = $acct.Translate([System.Security.Principal.SecurityIdentifier]).Value

                    # Només l'afegim si no està ja a la llista (evitem duplicats si un usuari té diversos explorer.exe)
                    if ($FoundSIDs -notcontains $sid) {
                        $FoundSIDs += $sid
                    }
                } catch {
                    # Si falla la traducció d'un SID concret, continuem amb el següent
                }
            }
        }
    } catch {
        $FoundSIDs = @()
    }

    # Si hem trobat algun SID → cachejar i marcar com comprovat
    if ($FoundSIDs.Count -gt 0) {
        $script:CachedLoggedOnSID = $FoundSIDs
        $script:CheckedLoggedOnSID = $true
        return $FoundSIDs
    }

    # Si NO hi ha usuaris → NO marcar CheckedLoggedOnSID per permetre re-intentar-ho
    return $null
}

# ---------------------------------------------------------------------------
# FUNCIONS DE PROCESSAMENT DE REGISTRE (CORE)
# ---------------------------------------------------------------------------

# Nivell més baix d'escriptura. Rep contingut de text i crea un fitxer .reg temporal amb la codificació correcta
# Executa de forma silenciosa regedit.exe /s per carregar el fitxer .reg temporal al registre
function Write-ContentToRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RegFileContents,

        # Els únics formats reals que un fitxer .reg pot tenir a la pràctica
        [ValidateSet('UTF16LE', 'ASCII', 'UTF8')]
        [string]$Encoding = 'UTF16LE',

        [switch]$EnableLogging,

        [string]$LogName = 'WriteHKCUFile',
        [string]$Component = 'ContentToRegistry'
    )

    $tempFile = Join-Path -Path ([IO.Path]::GetTempPath()) `
        -ChildPath ("reg_{0:yyyyMMddHHmmssff}.reg" -f (Get-Date))

    try {
        # Mapejar noms amigables als valors reals que fa servir Out-File
        switch ($Encoding) {
            'UTF16LE' { $realEncoding = 'Unicode' } # Format de reg.exe i regedit.exe des de Windows 2000
            'ASCII' { $realEncoding = 'ASCII' }   # Format d'arxius heretats REGEDIT4
            'UTF8' { $realEncoding = 'UTF8' }    # Format del bloc de notes, VSCode, etc.
        }

        $RegFileContents | Out-File -FilePath $tempFile -Encoding $realEncoding -Force

        if ($EnableLogging) {
            Write-Log "Fusionant el fitxer de registre $tempFile" -Level Info -UseCMTrace `
                -LogName $LogName -Component $Component
        }

        $process = Start-Process -FilePath regedit.exe `
            -ArgumentList "/s `"$tempFile`"" `
            -PassThru -Wait -WindowStyle Hidden

        $exitCode = $process.ExitCode

        if ($exitCode -ne 0) {
            if ($EnableLogging) {
                Write-Log "Error merging registry file. ExitCode: $exitCode" `
                    -Level Warning -UseCMTrace -LogName $LogName -Component $Component
            }
        } else {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        if ($EnableLogging) {
            Write-Log "Exception merging registry file: $_" -Level Error `
                -UseCMTrace -LogName $LogName -Component $Component
        }
    }
}

# La "intel·ligència" de l'script. Agafa el contingut del fitxer .reg original i substitueix totes les instàncies
# de HKEY_CURRENT_USER per la ruta corresponent dins de HKEY_USERS (ja sigui un SID o una branca temporal)
function Convert-ContentToHKUSubKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RegFileContents,

        # Pot ser un SID, una branca temporal TempUser, etc.
        [Parameter(Mandatory)]
        [string]$SubKeyName,

        [ValidateSet('UTF16LE', 'ASCII', 'UTF8')]
        [string]$Encoding = 'UTF16LE',

        [switch]$EnableLogging,

        [string]$LogName = 'WriteHKCUFile',
        [string]$Component = 'ContentToHKUSubKey'
    )

    if ($EnableLogging) {
        Write-Log "Transformant HKEY_CURRENT_USER to HKEY_USERS\$SubKeyName" -Level Info `
            -UseCMTrace -LogName $LogName -Component $Component
    }

    # Fem la substitució a l'array d'strings (tractant el guió com un literal de Regex)
    $TransformedContents = $RegFileContents -replace 'HKEY_CURRENT_USER', "HKEY_USERS\$SubKeyName"

    # Crida a la funció amb splatting de paràmetres perquè quedi més polit visualment
    $params = @{
        RegFileContents = $TransformedContents
        Encoding        = $Encoding
        EnableLogging   = $EnableLogging
        LogName         = $LogName
        Component       = $Component
    }

    Write-ContentToRegistry @params
}

# ---------------------------------------------------------------------------
# FUNCIONS D'ÀMBIT (SCOPE FUNCTIONS)
# ---------------------------------------------------------------------------

# Gestor de perfils individuals. És capaç de detectar si un perfil ja està carregat (encara que sigui en segon pla)
# per escriure directament a la seva clau de HKU, o muntar-ne el fitxer físic si l'usuari no ha iniciat sessió
function Write-RegistryProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfilePath,

        [Parameter(Mandatory)]
        [string[]]$RegFileContents,

        [ValidateSet('UTF16LE', 'ASCII', 'UTF8')]
        [string]$Encoding = 'UTF16LE',

        [switch]$EnableLogging,

        [string]$LogName = 'WriteHKCUFile',
        [string]$Component = 'RegistryProfilePath'
    )

    $HivePath = Join-Path -Path $ProfilePath -ChildPath "NTUSER.DAT"

    # 1. Verificar si existeix el fitxer NTUSER.DAT
    if (-not (Test-Path $HivePath)) {
        if ($EnableLogging) {
            Write-Log "No s'ha trobat NTUSER.DAT a $ProfilePath" -Level Error `
                -UseCMTrace -LogName $LogName -Component $Component
        }
        return
    }

    # 2. Lògica intel·ligent: Està ja carregat aquest perfil?
    # Busquem el SID que correspon a aquest ProfilePath al registre de Windows
    $ProfileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $sid = (Get-ChildItem -Path $ProfileListPath | Where-Object {
            (Get-ItemProperty $_.PSPath).ProfileImagePath -eq $ProfilePath
        } | Select-Object -ExpandProperty PSChildName -First 1)

    if ($sid -and (Get-Item -Path "Registry::HKEY_USERS\$sid" -ErrorAction SilentlyContinue)) {
        if ($EnableLogging) {
            Write-Log "El perfil de $ProfilePath ja està carregat (SID: $sid). S'aplicarà sense muntar el Hive." -Level Info `
                -UseCMTrace -LogName $LogName -Component $Component
        }
        Convert-ContentToHKUSubKey -RegFileContents $RegFileContents `
            -SubKeyName $sid `
            -Encoding $Encoding `
            -EnableLogging:($EnableLogging) `
            -LogName $LogName `
            -Component $Component
        return # Sortim perquè ja hem acabat amb aquest usuari
    }

    # 3. Si no està carregat, procedim amb el muntatge temporal
    $ProfileFolderName = Split-Path $ProfilePath -Leaf
    $TempHiveName = "TempHive_$ProfileFolderName"

    try {
        if ($EnableLogging) {
            Write-Log "Carregant Hive de $ProfilePath a HKU\$TempHiveName" -Level Info `
                -UseCMTrace -LogName $LogName -Component $Component
        }

        $load = Start-Process -FilePath reg.exe -ArgumentList "load `"HKU\$TempHiveName`" `"$HivePath`"" `
            -PassThru -Wait -WindowStyle Hidden

        if ($load.ExitCode -ne 0) { throw "Error en carregar el Hive del perfil (ExitCode: $($load.ExitCode))." }

        Convert-ContentToHKUSubKey -RegFileContents $RegFileContents `
            -SubKeyName $TempHiveName `
            -Encoding $Encoding `
            -EnableLogging:($EnableLogging) `
            -LogName $LogName `
            -Component $Component

    } catch {
        if ($EnableLogging) {
            Write-Log "Error processant ProfilePath ($ProfilePath): $_" -Level Error -UseCMTrace -LogName $LogName -Component $Component
        }
    } finally {
        # Neteja de seguretat: només si hem aconseguit carregar-lo
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()

        # Intentem descarregar només si existeix la clau temporal
        if (Test-Path "HKU:\$TempHiveName") {
            Start-Process -FilePath reg.exe -ArgumentList "unload `"HKU\$TempHiveName`"" `
                -PassThru -Wait -WindowStyle Hidden | Out-Null
        }
    }
}

# S'encarrega d'aplicar el fitxer .reg al perfil que Windows fa servir de plantilla per a nous usuaris
# Munta el fitxer NTUSER.DAT de la carpeta Default, aplica els canvis i el desmunta
function Write-RegistryDefaultUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RegFileContents,

        [ValidateSet('UTF16LE', 'ASCII', 'UTF8')]
        [string]$Encoding = 'UTF16LE',

        [switch]$EnableLogging,

        [string]$LogName = 'WriteHKCUFile',
        [string]$Component = 'RegistryDefaultUser'
    )

    $DefaultUserHive = "$env:SystemDrive\Users\Default\NTUSER.DAT"
    $TempHiveName = "TempDefaultUser" # Nom temporal a HKU

    # 1. Verificar si existeix el fitxer de Hive
    if (-not (Test-Path $DefaultUserHive -PathType Leaf)) {
        if ($EnableLogging) {
            Write-Log "No s'ha trobat NTUSER.DAT a $DefaultUserHive" -Level Error `
                -UseCMTrace -LogName $LogName -Component $Component
        }
        return
    }

    try {
        if ($EnableLogging) {
            Write-Log "Carregant Hive del Default User a HKEY_USERS\$TempHiveName" -Level Info `
                -UseCMTrace -LogName $LogName -Component $Component
        }

        # 2. Carregar el Hive del Default User mitjançant reg.exe
        $loadProcess = Start-Process -FilePath reg.exe `
            -ArgumentList "load `"HKU\$TempHiveName`" `"$DefaultUserHive`"" `
            -PassThru -Wait -WindowStyle Hidden

        if ($loadProcess.ExitCode -ne 0) { throw "Error en carregar el Hive del Default User." }

        # 3. Cridar a la funció de transformació anterior passant el nom del Hive temporal com a nom de SubClau
        Convert-ContentToHKUSubKey -RegFileContents $RegFileContents `
            -SubKeyName $TempHiveName `
            -Encoding $Encoding `
            -EnableLogging:($EnableLogging) `
            -LogName $LogName `
            -Component $Component

    } catch {
        if ($EnableLogging) {
            Write-Log "Error processant Default User: $_" -Level Error `
                -UseCMTrace -LogName $LogName -Component $Component
        }
    } finally {
        # 4. Neteja. Descarregar el Hive sí o sí (per això s'utilitza finally)
        # Es força el Garbage Collector per alliberar l'arxiu si algún procès l'ha fet servir
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()

        if ($EnableLogging) {
            Write-Log "Descarregant Hive HKEY_USERS\$TempHiveName" -Level Info `
                -UseCMTrace -LogName $LogName -Component $Component
        }

        Start-Process -FilePath reg.exe `
            -ArgumentList "unload `"HKU\$TempHiveName`"" `
            -PassThru -Wait -WindowStyle Hidden | Out-Null
    }
}

# Aplica els canvis exclusivament a l'usuari que està utilitzant l'equip en el moment de l'execució
function Write-RegistryCurrentUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RegFileContents,
        [string]$Encoding = 'UTF16LE',
        [switch]$EnableLogging,
        [string]$LogName = 'WriteHKCUFile',
        [string]$Component = 'RegistryCurrentUser'
    )

    $sids = Get-LoggedOnUserSID # Ara és un array

    if ($sids) {
        foreach ($sid in $sids) {
            if ($EnableLogging) {
                $userName = Get-UsernameFromSID $sid
                $displayText = if ($userName) { "$userName ($sid)" } else { $sid }
                Write-Log "Processant usuari loguejat: $displayText" -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }

            Convert-ContentToHKUSubKey -RegFileContents $RegFileContents `
                -SubKeyName $sid `
                -Encoding $Encoding `
                -EnableLogging:($EnableLogging) `
                -LogName $LogName `
                -Component $Component
        }
    } else {
        if ($EnableLogging) {
            Write-Log "No s'ha trobat cap usuari amb sessió activa" -Level Info -UseCMTrace -LogName $LogName -Component $Component
        }
    }
}

# Funció mestra que itera per tots els perfils d'usuari reals registrats a la màquina
# i crida a les funcions anteriors per assegurar que tothom rep la configuració del registre
# A l'hora d'obtenir els perfils des ProfileList cal evitar perfils especials (p.ex. SYSTEM):
# - S-1-5-18 = SYSTEM
# - S-1-5-19 = LocalService
# - S-1-5-20 = NetworkService
# - S-1-5-21-xxxxxxxxx-xxxxxxxxx-xxxxxxxxxx-xxxx (SID d'usuari local; 1000
# - S-1-5-21-xxxxxxxxx-xxxxxxxxx-xxxxxxxxxx-500 = Built-In Administrator
# - S-1-5-21-xxxxxxxxx-xxxxxxxxx-xxxxxxxxxx-1000 = 1st User (p.ej. defaultuser0)
# - S-1-12-1-xxxxxxxxx-xxxxxxxxx-xxxxxxxxxx-xxxxxxxxxx (SID d'usuari d'Entra ID) -> AzureAD\Username
# - S-1-110-1-xxxxxxxxx-xxxxxxxxx-xxxxxxxxxx-xxxxxxxxxx (SID de CloudAP, Cloud Authentication Provider)
function Write-RegistryAllUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RegFileContents,
        [string]$Encoding = 'UTF16LE',
        [switch]$EnableLogging,
        [string]$LogName = 'WriteHKCUFile',
        [string]$Component = 'RegistryAllUsers'
    )

    # Obtenim el SID de qui està executant l'script actualment
    $CurrentProcessSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    $ProfileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    
    # Filtre ampliat per incloure usuaris d'Entra ID (S-1-12-1)
    $UserProfiles = Get-ChildItem -Path $ProfileListPath | Where-Object { 
        $_.PSChildName -like "S-1-5-21-*" -or $_.PSChildName -like "S-1-12-1-*" 
    }

    foreach ($UserProfile in $UserProfiles) {
        $sid = $UserProfile.PSChildName
        $userName = Get-UsernameFromSID $sid
        $profilePath = Get-ProfilePathFromSID $sid
        $displayText = if ($userName) { "'$userName' ($sid)" } else { $sid }

        # 1. FILTRE: Saltem l'usuari de sistema d'Autopilot
        if ($userName -eq "defaultuser0") {
            Write-Log "Descartant usuari $displayText" -Level Info -UseCMTrace -LogName $LogName -Component $Component
            continue 
        }

        if ($EnableLogging) {
            Write-Log "Processant usuari $displayText" -Level Info -UseCMTrace -LogName $LogName -Component $Component
        }

        # 2. LÒGICA ESPECIAL: Som nosaltres mateixos?
        if ($sid -eq $CurrentProcessSID) {
            if ($EnableLogging) {
                Write-Log "L'usuari coincideix amb l'executor d'aquest script. Aplicant fitxer .reg original a HKCU..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }
            # Per a l'usuari actual NO fem el replace de HKEY_CURRENT_USER
            Write-ContentToRegistry -RegFileContents $RegFileContents `
                -Encoding $Encoding `
                -EnableLogging:($EnableLogging) `
                -LogName $LogName `
                -Component $Component
            continue
        }

        # 3. LÒGICA ESTÀNDARD: Per a la resta d'usuaris
        # Usem Get-Item amb el provider Registry:: en comptes de Test-Path HKU: per fiabilitat amb SIDs d'Entra ID
        if (Get-Item -Path "Registry::HKEY_USERS\$sid" -ErrorAction SilentlyContinue) {
            if ($EnableLogging) {
                Write-Log "El perfil JA està carregat a HKU. Aplicant directament a HKU..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }
            Convert-ContentToHKUSubKey -RegFileContents $RegFileContents `
                -SubKeyName $sid `
                -Encoding $Encoding `
                -EnableLogging:($EnableLogging) `
                -LogName $LogName `
                -Component $Component
        } else {
            # El perfil NO està carregat, hem de muntar el NTUSER.DAT
            if ($EnableLogging) {
                Write-Log "El perfil NO està carregat. Muntant fitxer NTUSER.DAT..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }
            Write-RegistryProfilePath -ProfilePath $profilePath `
                -RegFileContents $RegFileContents `
                -Encoding $Encoding `
                -EnableLogging:($EnableLogging) `
                -LogName $LogName `
                -Component $Component
        }
    }
}

# ---------------------------------------------------------------------------
# Script principal
# ---------------------------------------------------------------------------

$LogName = "WriteHKCUFile"
$Component = "Main"

if (-not (Test-Path -Path $RegFile)) {
    Write-Log "El fitxer $RegFile no existeix. Operació abortada" -Level Error -UseCMTrace -LogName $LogName -Component $Component
    exit 1
}

if ($CurrentUser -or $AllUsers -or $DefaultProfile) {

    $registryData = Get-Content -Path $RegFile -Raw
    Write-Log "S'ha carregat el fitxer de registre $RegFile" -Level Info -UseCMTrace -LogName $LogName -Component $Component

    $params = @{
        RegFileContents = $registryData
        EnableLogging   = $true
        LogName         = $LogName
    }

    if ($CurrentUser) {
        Write-Log "Aplicant fitxer de registre a 'CurrentUser'..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
        Write-RegistryCurrentUser @params -Component "CurrentUserMode"
    }

    if ($AllUsers) {
        Write-Log "Aplicant fitxer de registre a 'AllUsers'..." -Level Info -UseCMTrace -LogName $LogName -Component $Component        
        Write-RegistryAllUsers @params -Component "AllUsersMode"
    }

    if ($DefaultProfile) {
        Write-Log "Aplicant fitxer de registre a 'DefaultProfile'..." -Level Info -UseCMTrace -LogName $LogName -Component $Component        
        Write-RegistryDefaultUser @params -Component "DefaultProfileMode"
    }

} else {
    Write-Log 'Cap mode seleccionat (-CurrentUser, -AllUsers o -DefaultProfile). Operació abortada' -Level Warning -UseCMTrace -LogName $LogName -Component $Component
}
