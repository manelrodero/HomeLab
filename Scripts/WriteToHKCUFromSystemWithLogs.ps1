# Fitxer UTF-8 with BOM per escriure accents i caràcters especials

# Writing Current User registry keys in SCCM as System
# https://tdemeul.bunnybesties.org/2022/04/writing-current-user-registry-keys-in.html

# Modificado 27/06/2022 para UPC (Entorno GET)
# Modificado 16/07/2025 para UPC (Entorno mGET)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\.reg$')]
    [string]$RegFile,

    [switch]$CurrentUser,
    [switch]$AllUsers,
    [switch]$DefaultProfile
)

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [bool]$Output = $false,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info",

        [Parameter(Mandatory = $false)]
        [string]$Component = $(Split-Path -Leaf $MyInvocation.PSCommandPath).Replace('.ps1', ''),

        [Parameter(Mandatory = $false)]
        [string]$LogName = $(Split-Path -Leaf $MyInvocation.PSCommandPath).Replace('.ps1', ''),

        [Parameter(Mandatory = $false)]
        [switch]$UseCMTrace
    )

    # Determinar ruta del log si no s'ha especificat
    # 1) Intune: $env:ProgramData\Microsoft\IntuneManagementExtension\Logs
    # 2) Subdirectori del script: $PSScriptRoot\Logs
    # 3) $env:TEMP\Logs
    $defaultLogDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
    if (-not (Test-Path $defaultLogDir)) {
        $defaultLogDir = "$PSScriptRoot\Logs"
        if (-not (Test-Path $defaultLogDir)) {
            $defaultLogDir = "$env:TEMP\Logs"
            if (-not (Test-Path $defaultLogDir)) {
                New-Item -Path $defaultLogDir -ItemType Directory | Out-Null
            }
        }
    }
    $LogFile = "$defaultLogDir\UPC-$LogName.log"

    if ($UseCMTrace) {
        # Format CMTrace
        $typeMap = @{ "Info" = "1"; "Warning" = "2"; "Error" = "3" }
        $timestamp = Get-Date
        $logEntry = "<![LOG[$Message]LOG]!>" +
        "<time=""{0}"" date=""{1}"" component=""{2}"" context=""{3}"" type=""{4}"" thread="""" file="""">" -f `
            $timestamp.ToString("HH:mm:ss.ffffff"),
        $timestamp.ToString("M-d-yyyy"),
        $Component,
        $env:USERNAME,
        $typeMap[$Level]
    } else {
        # Format text pla amb timestamp
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "$timestamp [$Level] $Component :: $Message"
    }

    $logEntry | Out-File -FilePath $LogFile -Append -Encoding utf8

    if ($Output) {
        Write-Output $logEntry
    }
}

function Write-Registry {
    param($RegFileContents)
    $tempFile = '{0}{1:yyyyMMddHHmmssff}.reg' -f [IO.Path]::GetTempPath(), (Get-Date)
    $RegFileContents | Out-File -FilePath $tempFile
    Write-Log ('Writing registry from file {0}' -f $tempFile) -Level Info -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
    try { $p = Start-Process -FilePath C:\Windows\regedit.exe -ArgumentList "/s $tempFile" -PassThru -Wait } catch { }
    if ($null -ne $p) { $exitCode = $p.ExitCode } else { $exitCode = 0 }
    if ($exitCode -ne 0) {
        Write-Log 'There was an error merging the reg file' -Level Warning -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
    } else {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -Path $RegFile)) {
    Write-Log "RegFile $RegFile doesn't exist. Operation aborted" -Level Error -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
} else {

    if ($CurrentUser -or $AllUsers -or $DefaultProfile) {

        Write-Log ('Reading the registry file {0}' -f $RegFile) -Level Info -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
        $registryData = Get-Content -Path $RegFile -ReadCount 0

        if ($CurrentUser) {
            Write-Log "Writing to the currenlty logged on user's registry" -Level Info -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
            $explorers = Get-WmiObject -Namespace root\cimv2 -Class Win32_Process -Filter "Name='explorer.exe'"
            $explorers | ForEach-Object {
                $owner = $_.GetOwner()
                if ($owner.ReturnValue -eq 0) {
                    $user = '{0}\{1}' -f $owner.Domain, $owner.User
                    $ntAccount = New-Object -TypeName System.Security.Principal.NTAccount($user)
                    $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
                    $RegFileContents = $registryData -replace 'HKEY_CURRENT_USER', "HKEY_USERS\$sid"
                    Write-Registry -RegFileContents $RegFileContents
                }
            }
        }

        if ($AllUsers) {
            Write-Log "Writing to every user's registry" -Level Info -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
            $res = C:\Windows\system32\reg.exe query HKEY_USERS
            $res -notmatch 'S-1-5-18|S-1-5-19|S-1-5-20|DEFAULT|Classes' | ForEach-Object {
                if ($_ -ne '') {
                    $sid = $_ -replace 'HKEY_USERS\\'
                    $RegFileContents = $registryData -replace 'HKEY_CURRENT_USER', "HKEY_USERS\$sid"
                    Write-Log "- $sid" -Level Info -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
                    Write-Registry -RegFileContents $RegFileContents
                }
            }
        }

        if ($DefaultProfile) {
            Write-Log "Writing to the default profile's registry (for future users)" -Level Info -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
            C:\Windows\System32\reg.exe load 'HKU\DefaultUser' C:\Users\Default\NTUSER.DAT | Out-Null
            $RegFileContents = $registryData -replace 'HKEY_CURRENT_USER', 'HKEY_USERS\DefaultUser'
            Write-Registry -RegFileContents $RegFileContents
            C:\Windows\System32\reg.exe unload 'HKU\DefaultUser' | Out-Null
        }

    } else {
        Write-Log 'No mode was selected. Operation aborted' -Level Warning -UseCMTrace -LogName "LogName" -Component "WriteToHKCUFromSystem"
    }
}
