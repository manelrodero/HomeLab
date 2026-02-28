# Fitxer UTF-8 with BOM per escriure accents i caràcters especials

# Adaptació de l'script 'WriteToHKCUFromSystemWithLogsNG.ps1'
# Escriu claus individuals amb reg.exe en lloc d'un fitxer de registre amb regedit.exe

# ---------------------------------------------------------------------------
# FUNCIONS DE SUPORT (HELPER FUNCTIONS)
# ---------------------------------------------------------------------------

function Write-Log {
    param (
        [Parameter(Mandatory = $true)] [string]$Message,
        [Parameter(Mandatory = $false)] [bool]$Output = $false,
        [Parameter(Mandatory = $false)] [bool]$OriginalOutput = $false,
        [Parameter(Mandatory = $false)] [bool]$ShowHost = $false,
        [Parameter(Mandatory = $false)] [ValidateSet("Info", "Warning", "Error")] [string]$Level = "Info",
        [Parameter(Mandatory = $false)] [string]$Component = "RegistryWriter",
        [Parameter(Mandatory = $false)] [string]$LogName = "WriteHKCURegExe",
        [Parameter(Mandatory = $false)] [switch]$UseCMTrace,
        [Parameter(Mandatory = $false)] [bool]$InitFile = $false
    )

    # 1. GENERAR EL MISSATGE
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

    # 2. SORTIDA A CONSOLA (Només si ShowHost és $true)
    if ($ShowHost) {
        $color = "White"
        if ($Level -eq "Warning") { $color = "Yellow" }
        if ($Level -eq "Error") { $color = "Red" }
        Write-Host "[$Level] [$Component] $Message" -ForegroundColor $color
    }

    # 3. LÒGICA D'ESCRIPTURA ITERATIVA
    $LogPaths = @(
        "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs",
        "$PSScriptRoot\Logs",
        "$env:TEMP\Logs",
        "$env:TEMP"
    )

    $Success = $false

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

            $Success = $true
            break
        } catch {
            continue
        }
    }

    if (-not $Success -and $ShowHost) {
        Write-Host "[LOG ERROR] No s'ha pogut guardar el fitxer de log a cap de les rutes permeses." -ForegroundColor Red
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
    try { return (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath } catch { return $null }
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
    if ($script:CheckedLoggedOnSID -and $script:CachedLoggedOnSID) { return $script:CachedLoggedOnSID }

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
                    if ($FoundSIDs -notcontains $sid) { $FoundSIDs += $sid }
                } catch {
                    # Si falla la traducció d'un SID concret, continuem amb el següent
                }
            }
        }
    } catch { $FoundSIDs = @() }

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

function Set-RegistryValueDirect {
    param(
        [string]$FullKeyPath,
        [string]$ValueName,
        [string]$Type,
        [string]$Data,
        [switch]$EnableLogging,
        [bool]$ShowHost = $false,
        [string]$LogName = 'WriteHKCURegExe',
        [string]$Component = 'RegistryValueDirect'
    )

    if ($EnableLogging) {
        Write-Log "Intentant escriure a $FullKeyPath" -Level Info -UseCMTrace -ShowHost $ShowHost -LogName $LogName -Component $Component
        Write-Log "Valor: $ValueName | Tipus: $Type | Dades: $Data" -Level Info -UseCMTrace -ShowHost $ShowHost -LogName $LogName -Component $Component
    }

    $process = Start-Process -FilePath "reg.exe" `
        -ArgumentList "add `"$FullKeyPath`" /v `"$ValueName`" /t $Type /d `"$Data`" /f /reg:64" `
        -PassThru -Wait -WindowStyle Hidden

    if ($process.ExitCode -ne 0) {
        if ($EnableLogging) { Write-Log "Error de reg.exe escrivint a $FullKeyPath. ExitCode: $($process.ExitCode)" -Level Error -ShowHost $ShowHost -LogName $LogName -Component $Component }
    } elseif ($EnableLogging) {
        Write-Log "Dades escrites correctament a $FullKeyPath" -Level Info -UseCMTrace -ShowHost $ShowHost -LogName $LogName -Component $Component
    }
}

# ---------------------------------------------------------------------------
# FUNCIONS D'ÀMBIT (SCOPE FUNCTIONS)
# ---------------------------------------------------------------------------

# Gestor de perfils individuals. És capaç de detectar si un perfil ja està carregat (encara que sigui en segon pla)
# per escriure directament a la seva clau de HKU, o muntar-ne el fitxer físic si l'usuari no ha iniciat sessió
function Write-RegistryProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ProfilePath,
        [Parameter(Mandatory)] [string]$SubKey,
        [Parameter(Mandatory)] [string]$ValueName,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$Data,
        [switch]$EnableLogging,
        [bool]$ShowHost = $false,
        [string]$LogName = 'WriteHKCURegExe',
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
        Set-RegistryValueDirect -FullKeyPath "HKU\$sid\$SubKey" -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
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

        $load = Start-Process -FilePath reg.exe -ArgumentList "load `"HKU\$TempHiveName`" `"$HivePath`"" -PassThru -Wait -WindowStyle Hidden
        if ($load.ExitCode -ne 0) { throw "Error en carregar el Hive del perfil (ExitCode: $($load.ExitCode))." }
        Set-RegistryValueDirect -FullKeyPath "HKU\$TempHiveName\$SubKey" -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
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
            Start-Process -FilePath reg.exe -ArgumentList "unload `"HKU\$TempHiveName`"" -PassThru -Wait -WindowStyle Hidden | Out-Null
        }
    }
}

# S'encarrega d'escriure al registre del perfil que Windows fa servir de plantilla per a nous usuaris
# Munta el fitxer NTUSER.DAT de la carpeta Default, aplica els canvis i el desmunta
function Write-RegistryDefaultUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SubKey,
        [Parameter(Mandatory)] [string]$ValueName,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$Data,
        [switch]$EnableLogging,
        [bool]$ShowHost = $false,
        [string]$LogName = 'WriteHKCURegExe',
        [string]$Component = 'RegistryDefaultUser'
    )

    $DefaultUserHive = "$env:SystemDrive\Users\Default\NTUSER.DAT"
    $TempHiveName = "TempDefaultUser"

    # 1. Verificar si existeix el fitxer de Hive
    if (-not (Test-Path $DefaultUserHive)) {
        Write-Log "No s'ha trobat NTUSER.DAT a $DefaultUserHive" -Level Error `
            -UseCMTrace -LogName $LogName -Component $Component
        return
    }

    try {
        if ($EnableLogging) {
            Write-Log "Carregant Hive del Default User a HKEY_USERS\$TempHiveName" -Level Info `
                -UseCMTrace -LogName $LogName -Component $Component
        }

        # 2. Carregar el Hive del Default User mitjançant reg.exe
        $load = Start-Process -FilePath reg.exe -ArgumentList "load `"HKU\$TempHiveName`" `"$DefaultUserHive`"" -PassThru -Wait -WindowStyle Hidden
        if ($load.ExitCode -ne 0) { throw "Error en carregar el Hive del Default User." }

        # 3. Cridar a la funció per escriure al registre passant el nom del Hive temporal com a nom de SubClau
        Set-RegistryValueDirect -FullKeyPath "HKU\$TempHiveName\$SubKey" -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
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

        Start-Process -FilePath reg.exe -ArgumentList "unload `"HKU\$TempHiveName`"" -PassThru -Wait -WindowStyle Hidden | Out-Null
    }
}

# Aplica els canvis exclusivament a l'usuari que està utilitzant l'equip en el moment de l'execució
function Write-RegistryCurrentUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SubKey,
        [Parameter(Mandatory)] [string]$ValueName,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$Data,
        [switch]$EnableLogging,
        [bool]$ShowHost = $false,
        [string]$LogName = 'WriteHKCURegExe',
        [string]$Component = 'RegistryCurrentUser'
    )

    $sids = Get-LoggedOnUserSID
    if ($sids) {
        foreach ($sid in $sids) {
            if ($EnableLogging) {
                $userName = Get-UsernameFromSID $sid
                $displayText = if ($userName) { "$userName ($sid)" } else { $sid }
                Write-Log "Processant usuari loguejat: $displayText" -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }

            Set-RegistryValueDirect -FullKeyPath "HKU\$sid\$SubKey" -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
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
        [Parameter(Mandatory)] [string]$SubKey,
        [Parameter(Mandatory)] [string]$ValueName,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$Data,
        [switch]$EnableLogging,
        [bool]$ShowHost = $false,
        [string]$LogName = 'WriteHKCURegExe',
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

        # 2. LÒGICA ESPECIAL: Som nosaltres mateixos?
        if ($sid -eq $CurrentProcessSID) {
            if ($EnableLogging) {
                Write-Log "L'usuari coincideix amb l'executor d'aquest script. Escrivint a HKCU..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }

            Set-RegistryValueDirect -FullKeyPath "HKCU\$SubKey" -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
            continue
        }

        # 3. LÒGICA ESTÀNDARD: Per a la resta d'usuaris
        # Usem Get-Item amb el provider Registry:: en comptes de Test-Path HKU: per fiabilitat amb SIDs d'Entra ID
        if (Get-Item -Path "Registry::HKEY_USERS\$sid" -ErrorAction SilentlyContinue) {
            if ($EnableLogging) {
                Write-Log "El perfil JA està carregat a HKU. Escrivint directament a HKU..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }
            Set-RegistryValueDirect -FullKeyPath "HKU\$sid\$SubKey" -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
        } else {
            # El perfil NO està carregat, hem de muntar el NTUSER.DAT
            if ($EnableLogging) {
                Write-Log "El perfil NO està carregat. Muntant fitxer NTUSER.DAT..." -Level Info -UseCMTrace -LogName $LogName -Component $Component
            }
            Write-RegistryProfilePath -ProfilePath $pPath -SubKey $SubKey -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost -LogName $LogName -Component $Component
        }
    }
}

# Wrapper per escriure al Default User i a qualsevol usuari que hagi iniciat sessió
function Write-RegistryDefaultAndCurrentUser {
    param($SubKey, $ValueName, $Type, $Data, [switch]$EnableLogging, [bool]$ShowHost = $false)
    Write-RegistryDefaultUser -SubKey $SubKey -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost
    Write-RegistryCurrentUser -SubKey $SubKey -ValueName $ValueName -Type $Type -Data $Data -EnableLogging:$EnableLogging -ShowHost $ShowHost
}

# Exemples d'ús d'aquestes funcions (això no es copia al nostre script)
# Write-RegistryDefaultAndCurrentUser "Software\UPC\WriteToHKCU-Test" "FromRegExe" "REG_DWORD" "1" -EnableLogging:$true -LogName "WriteHKCURegExe" -Component "Main"
# Write-RegistryDefaultAndCurrentUser "Software\UPC\WriteToHKCU-Test" "FromRegExe" "REG_SZ" "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -EnableLogging:$true -LogName "WriteHKCURegExe" -ShowHost:$true
