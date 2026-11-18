<#
  Instalace Jellyfin Serveru jako služby Windows + firewall jen pro domácí síť.
  Spouštět ve zvýšeném PowerShellu (Spustit jako správce).

  Použití:
    .\1_install_server.ps1 -Installer C:\Downloads\jellyfin_12.4_windows-x64.exe

  Instalačka: https://jellyfin.org/downloads/windows (ověřte SHA256 ze stránky vydání)
#>
param(
  [Parameter(Mandatory)] [string] $Installer
)
$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
  throw 'Spusťte PowerShell jako správce.'
}

# 1) Tichá instalace: výchozí volby = služba "JellyfinServer" (NetworkService), data v C:\ProgramData\Jellyfin\Server
$p = Start-Process $Installer -ArgumentList '/S' -Wait -PassThru
"Instalátor skončil s kódem $($p.ExitCode)"

# 2) Firewall: jen profil Private a jen místní podsíť (z internetu nic)
foreach ($r in @(
    @{ Name = 'Jellyfin HTTP (8096)';      Proto = 'TCP'; Port = 8096 },
    @{ Name = 'Jellyfin discovery (7359)'; Proto = 'UDP'; Port = 7359 })) {
  Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol $r.Proto `
    -LocalPort $r.Port -Profile Private -RemoteAddress LocalSubnet | Out-Null
  "Firewall: $($r.Name)"
}

# 3) Automatický start s Windows + restart při pádu (3x po 60 s)
Set-Service JellyfinServer -StartupType Automatic
sc.exe failure JellyfinServer reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
if ((Get-Service JellyfinServer).Status -ne 'Running') { Start-Service JellyfinServer }

Get-Service JellyfinServer | Format-List Name, Status, StartType
'Hotovo. Síť počítače musí mít profil "Soukromá" (Get-NetConnectionProfile), jinak TV server neuvidí.'
