<#
  Prvotní nastavení Jellyfinu PŘED dokončením průvodce (tyto endpointy jsou do té doby anonymní).
  Nastaví jazyk/zemi a vytvoří knihovnu filmů jen pro čtení (nic se neukládá do složek s filmy).

  Použití – jedna knihovna:
    .\2_setup_library.ps1 -MediaPath 'D:\FILMY' -ServerName 'FILMY'

  Použití – víc knihoven (např. filmy podle jazyka dabingu; každá složka = vlastní dlaždice v aplikaci):
    .\2_setup_library.ps1 -ServerName 'FILMY' -Libraries @{ 'Filmy' = 'D:\FILMY\CZ'; 'UA filmy' = 'D:\FILMY\UA' }

  Pak v prohlížeči http://localhost:8096 dokončete průvodce (účet správce si zakládáte sami)
  a NEZAPOMEŇTE kliknout až na poslední "Hotovo" (viz README – Řešení problémů).
  Po dokončení průvodce se další knihovny přidávají ve webovém rozhraní (viz README – Víc knihoven).
#>
param(
  [string]    $MediaPath  = 'D:\FILMY',
  [string]    $LibraryName = 'Filmy',
  [hashtable] $Libraries,
  [string]    $ServerName = 'FILMY',
  [string]    $Server     = 'http://localhost:8096'
)
$ErrorActionPreference = 'Stop'
$json = 'application/json; charset=utf-8'
function Send($url, $method, $obj) {
  $body = if ($obj) { [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 6)) } else { $null }
  Invoke-RestMethod $url -Method $method -ContentType $json -Body $body
}
if (-not $Libraries) { $Libraries = @{ $LibraryName = $MediaPath } }

Send "$Server/Startup/Configuration" Post @{ ServerName = $ServerName; UICulture = 'cs'; MetadataCountryCode = 'CZ'; PreferredMetadataLanguage = 'cs' }
'Jazyk a země nastaveny'

$existing = @(Invoke-RestMethod "$Server/Library/VirtualFolders" | ForEach-Object { $_ } | ForEach-Object Name)
foreach ($name in $Libraries.Keys) {
  $path = $Libraries[$name]
  if ($existing -contains $name) { "Knihovna $name už existuje"; continue }
  if (-not (Test-Path $path)) { throw "Složka neexistuje: $path" }
  $opts = @{ LibraryOptions = @{
      Enabled                                 = $true
      EnableRealtimeMonitor                   = $true    # nové/smazané soubory se projeví samy
      SaveLocalMetadata                       = $false   # žádné .nfo/obrázky do složek s filmy
      MetadataSavers                          = @()
      SaveSubtitlesWithMedia                  = $false
      SaveTrickplayWithMedia                  = $false
      EnableTrickplayImageExtraction          = $true    # náhledy při přetáčení (ukládají se do ProgramData)
      ExtractTrickplayImagesDuringLibraryScan = $false
      EnableChapterImageExtraction            = $false
      EnableEmbeddedTitles                    = $false
      EnableInternetProviders                 = $true
      PreferredMetadataLanguage               = 'cs'
      MetadataCountryCode                     = 'CZ'
      PathInfos                               = @(@{ Path = $path })
  } }
  $q = 'name=' + [uri]::EscapeDataString($name) + '&collectionType=movies&refreshLibrary=true&paths=' + [uri]::EscapeDataString($path)
  Send "$Server/Library/VirtualFolders?$q" Post $opts
  "Knihovna $name -> $path vytvořena"
}
