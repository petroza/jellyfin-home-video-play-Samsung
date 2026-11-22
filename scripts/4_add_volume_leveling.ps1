<#
  Přidá do aplikace Jellyfin pro TV (Jellyfin.wgt) tlačítko na vyrovnání hlasitosti.
  Během filmu: CH ▲ = Vypnuto -> Vyrovnat hlasitost -> Noční režim, CH ▼ = vypnout.

  Vezme původní Jellyfin.wgt, přidá do něj tv\vyrovnani.js a uloží NOVÝ balíček
  (originál zůstane beze změny). Ten pak nainstalujete obvyklým skriptem 3_install_tv.ps1,
  který ho podepíše. Aplikace se nainstaluje jako aktualizace, přihlášení na TV zůstane.

  Použití:
    .\4_add_volume_leveling.ps1 -Wgt C:\Downloads\Jellyfin.wgt
    # -> C:\Downloads\vyrovnani\Jellyfin.wgt
    .\3_install_tv.ps1 -Wgt C:\Downloads\vyrovnani\Jellyfin.wgt -TvIp ... -ExpectedModel ... -ExpectedMac ... -TizenRoot ...

  Návrat k původní aplikaci: nainstalujte stejným skriptem původní Jellyfin.wgt.
#>
param(
  [Parameter(Mandatory)] [string] $Wgt,
  [string] $OutDir = (Join-Path (Split-Path $Wgt) 'vyrovnani'),
  [string] $Script = (Join-Path $PSScriptRoot '..\tv\vyrovnani.js')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
foreach ($f in $Wgt, $Script) { if (-not (Test-Path $f)) { throw "Nenalezeno: $f" } }

# 1) Rozbalit do dočasné složky
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('jf_vyrovnani_' + [guid]::NewGuid().ToString('N'))
[IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $Wgt), $tmp)
try {
  # 2) Starý podpis pryč (balíček se podepíše znovu při instalaci)
  Get-ChildItem $tmp -File | Where-Object { $_.Name -match '^(author-signature|signature\d+)\.xml$' } | Remove-Item

  # 3) Skript do kořene balíčku + odkaz v www/index.html hned za tizen.js
  Copy-Item $Script (Join-Path $tmp 'vyrovnani.js') -Force
  $index = Join-Path $tmp 'www\index.html'
  $html  = [IO.File]::ReadAllText($index)
  if ($html -notmatch 'vyrovnani\.js') {
    $m = [regex]::Match($html, '<script[^>]*src="\.\./tizen\.js"[^>]*></script>')
    if (-not $m.Success) { throw 'V www/index.html chybí odkaz na ../tizen.js – jiná verze balíčku? Nic neměním.' }
    $tag  = '<script src="../vyrovnani.js" defer=""></script>'
    $html = $html.Insert($m.Index + $m.Length, $tag)
    [IO.File]::WriteAllText($index, $html, (New-Object Text.UTF8Encoding $false))
  }

  # 4) Zabalit zpět (cesty uvnitř zipu s lomítky '/', jak to Tizen vyžaduje)
  New-Item -ItemType Directory $OutDir -Force | Out-Null
  $out = Join-Path $OutDir (Split-Path $Wgt -Leaf)
  if (Test-Path $out) { Remove-Item $out }
  $zip = [IO.Compression.ZipFile]::Open($out, 'Create')
  try {
    $root = (Resolve-Path $tmp).Path.TrimEnd('\') + '\'
    Get-ChildItem $tmp -Recurse -File | ForEach-Object {
      $name = $_.FullName.Substring($root.Length).Replace('\', '/')
      [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $name, 'Optimal')
    }
  } finally { $zip.Dispose() }
  "Hotovo: $out"
  'Teď ho nainstalujte skriptem 3_install_tv.ps1 (parametr -Wgt na tento soubor).'
} finally {
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
