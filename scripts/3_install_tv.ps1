<#
  Nainstaluje aplikaci Jellyfin (.wgt) do televize Samsung (Tizen) v režimu vývojáře.
  Před instalací ověří, že na zadané IP je opravdu VAŠE televize (model + MAC).

  Předpoklady (viz README):
    - Tizen Studio CLI (web-cli) nainstalované, např. do C:\tizen-studio
    - Jellyfin.wgt stejné verze jako server (jeppevinkel/jellyfin-tizen-builds)
    - TV: Aplikace -> 1 2 3 4 5 -> Developer mode ON, Host PC IP = IP tohoto PC -> restart TV

  Použití:
    .\3_install_tv.ps1 -TvIp 192.168.1.20 -ExpectedModel UE70RU7092UXXH -ExpectedMac aa:bb:cc:dd:ee:ff `
                       -Wgt C:\Downloads\Jellyfin.wgt -TizenRoot C:\tizen-studio
#>
param(
  [Parameter(Mandatory)] [string] $TvIp,
  [Parameter(Mandatory)] [string] $ExpectedModel,
  [Parameter(Mandatory)] [string] $ExpectedMac,
  [Parameter(Mandatory)] [string] $Wgt,
  [Parameter(Mandatory)] [string] $TizenRoot,
  [string] $SecProfile = 'JELLYFIN'
)
$ErrorActionPreference = 'Stop'
$tizen = Join-Path $TizenRoot 'tools\ide\bin\tizen.bat'
$sdb   = Join-Path $TizenRoot 'tools\sdb.exe'
foreach ($f in $tizen, $sdb, $Wgt) { if (-not (Test-Path $f)) { throw "Nenalezeno: $f" } }
$norm = { param($m) ($m -replace '[^0-9a-fA-F]', '').ToLower() }

# 1) Je to opravdu moje televize?
$dev = (Invoke-RestMethod "http://${TvIp}:8001/api/v2/" -TimeoutSec 5).device
"TV na ${TvIp}: $($dev.name) / $($dev.modelName) / MAC $($dev.wifiMac) / $($dev.networkType)"
if ($dev.modelName -ne $ExpectedModel) { throw "Model nesedí (čekám $ExpectedModel). Konec, nic se neinstaluje." }
if ((& $norm $dev.wifiMac) -ne (& $norm $ExpectedMac)) { throw "MAC nesedí (čekám $ExpectedMac). Konec." }
$arp = Get-NetNeighbor -IPAddress $TvIp -ErrorAction SilentlyContinue | Select-Object -First 1
if ($arp -and (& $norm $arp.LinkLayerAddress) -ne (& $norm $ExpectedMac)) { throw "MAC v ARP tabulce nesedí. Konec." }
'Identita televize ověřena.'

# 2) Podpisový certifikát (vytvoří se jen jednou; heslo se uloží MIMO repozitář vedle Tizen Studia)
$dataPath = (Get-Content (Join-Path $TizenRoot 'sdk.info') | Where-Object { $_ -like 'TIZEN_SDK_DATA_PATH=*' }) -replace '^TIZEN_SDK_DATA_PATH='
$certDir  = Join-Path (Split-Path $TizenRoot) 'tizen-cert'
$pwFile   = Join-Path $certDir 'heslo_certifikatu.txt'
$profiles = & $tizen security-profiles list | Out-String
if ($profiles -notmatch "(?m)^$SecProfile\s") {
  New-Item -ItemType Directory $certDir -Force | Out-Null
  $pw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
  Set-Content $pwFile $pw -Encoding ascii
  & $tizen certificate -a $SecProfile -n $SecProfile -c CZ -p $pw -f ($SecProfile.ToLower())
  & $tizen security-profiles add -n $SecProfile -a (Join-Path $dataPath "keystore\author\$($SecProfile.ToLower()).p12") -p $pw
  "Certifikát vytvořen, heslo uloženo do $pwFile (nesdílet)."
}

# 3) Podepsat KOPII balíčku (originál zůstane beze změny)
$signedDir = Join-Path (Split-Path $Wgt) 'podepsany'
New-Item -ItemType Directory $signedDir -Force | Out-Null
$signed = Join-Path $signedDir (Split-Path $Wgt -Leaf)
Copy-Item $Wgt $signed -Force
& $tizen package -t wgt -s $SecProfile -- $signed

# 4) Připojit se jen k této TV a zkontrolovat seznam zařízení
& $sdb connect "${TvIp}:26101"
$devices = & $sdb devices | Select-String "^${TvIp}:26101\s+device\s+(\S+)"
if (-not $devices) { throw 'TV se nepřipojila – je zapnutý Developer mode s IP tohoto PC a TV po něm restartovaná?' }
$sdbName = $devices.Matches[0].Groups[1].Value
if ($sdbName -ne $ExpectedModel) { throw "sdb hlásí jiné zařízení ($sdbName). Konec." }

# 5) Instalace a spuštění
$out = & $tizen install -n $signed -s "${TvIp}:26101" | Out-String
$out
if ($out -match 'Installed the package: Id\(([^)]+)\)') {
  & $tizen run -p $Matches[1] -s "${TvIp}:26101"
  "Hotovo: aplikace $($Matches[1]) nainstalovaná a spuštěná."
} else { throw 'Instalace se nepovedla – viz výpis výše.' }
& $sdb disconnect "${TvIp}:26101" | Out-Null
