<#
  Prvotní nastavení Jellyfinu PŘED dokončením průvodce (tyto endpointy jsou do té doby anonymní).
  Nastaví jazyk/zemi a vytvoří knihovnu filmů jen pro čtení (nic se neukládá do složek s filmy).

  Použití:
    .\2_setup_library.ps1 -MediaPath 'D:\FILMY' -ServerName 'FILMY'

  Pak v prohlížeči http://localhost:8096 dokončete průvodce (účet správce si zakládáte sami)
  a NEZAPOMEŇTE kliknout až na poslední "Hotovo" (viz README – Řešení problémů).
#>
param(
  [string] $MediaPath  = 'D:\FILMY',
  [string] $ServerName = 'FILMY',
  [string] $Server     = 'http://localhost:8096'
)
$ErrorActionPreference = 'Stop'
$json = 'application/json; charset=utf-8'
function Send($url, $method, $obj) {
  $body = if ($obj) { [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 6)) } else { $null }
  Invoke-RestMethod $url -Method $method -ContentType $json -Body $body
}

Send "$Server/Startup/Configuration" Post @{ ServerName = $ServerName; UICulture = 'cs'; MetadataCountryCode = 'CZ'; PreferredMetadataLanguage = 'cs' }
'Jazyk a země nastaveny'

$existing = Invoke-RestMethod "$Server/Library/VirtualFolders"
if ($existing | Where-Object Name -eq 'Filmy') { 'Knihovna Filmy už existuje'; return }

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
    PathInfos                               = @(@{ Path = $MediaPath })
} }
$q = 'name=Filmy&collectionType=movies&refreshLibrary=true&paths=' + [uri]::EscapeDataString($MediaPath)
Send "$Server/Library/VirtualFolders?$q" Post $opts
"Knihovna Filmy -> $MediaPath vytvořena"
