#Requires -Modules Logging

# Write the QUAKE2_* settings into <QUAKE2_GAME or baseq2>/lancommander.cfg, which quake2-server
# execs before +map. The file is regenerated on every start; put your own settings in server.cfg
# next to it (in Overlay/), which lancommander.cfg execs first (last when QUAKE2_MAP is empty).

$game = if ($Env:QUAKE2_GAME) { $Env:QUAKE2_GAME } else { 'baseq2' }
$dir = Join-Path $Env:SERVER_ROOT $game
$file = Join-Path $dir 'lancommander.cfg'

if (-not (Test-Path -Path (Join-Path $Env:SERVER_ROOT 'baseq2/pak0.pak'))) {
    Write-Log -Level Error "baseq2/pak0.pak not found in $Env:SERVER_ROOT; copy the Quake II baseq2/ folder (pak0.pak, pak1.pak, pak2.pak) into $Env:SERVER_DIR"
    return
}

if ($game -ne 'baseq2' -and -not (Test-Path -Path $dir)) {
    Write-Log -Level Warning "QUAKE2_GAME=$game, but $dir doesn't exist; copy the mod folder into $Env:SERVER_DIR"
}

# A `map` line in server.cfg (the stock ctf/server.cfg ends with `map q2ctf1`) starts the server
# before the QUAKE2_* settings apply, and Q2PRO then ignores the launcher's +map. When QUAKE2_MAP
# picks the map, comment those lines out; the edited copy lands in Overlay/
$serverCfg = Join-Path $dir 'server.cfg'
if ($Env:QUAKE2_MAP -and (Test-Path -Path $serverCfg)) {
    $original = [System.IO.File]::ReadAllText($serverCfg)
    $pattern = '(?m)^([ \t]*)((?:map|gamemap|demomap)[ \t]+\S)'
    if ($original -match $pattern) {
        $edited = [regex]::Replace($original, $pattern, '$1// Disabled because QUAKE2_MAP is set: $2')
        [System.IO.File]::WriteAllText($serverCfg, $edited)
        chown "$($Env:UID):$($Env:GID)" $serverCfg
        Write-Log "Commented out the map command in $serverCfg, QUAKE2_MAP=$($Env:QUAKE2_MAP) picks the map"
    }
}

function ConvertTo-Quoted([string] $Value) { '"' + $Value.Replace('"', '') + '"' }

function ConvertTo-Bool([string] $Value) {
    if (-not $Value) { return $null }
    if ($Value -in 'true', '1', 'yes') { '1' } elseif ($Value -in 'false', '0', 'no') { '0' } else { $Value }
}

$deathmatch = $Env:QUAKE2_DEATHMATCH
$coop = ConvertTo-Bool $Env:QUAKE2_COOP

# deathmatch wins over coop, so co-op needs deathmatch 0
if ($coop -eq '1' -and $deathmatch -and $deathmatch -ne '0') {
    Write-Log -Level Warning "QUAKE2_COOP is on, so deathmatch is set to 0 instead of QUAKE2_DEATHMATCH=$deathmatch"
    $deathmatch = '0'
}

$values = [ordered]@{
    'hostname'          = $(if ($Env:QUAKE2_SERVER_NAME) { ConvertTo-Quoted $Env:QUAKE2_SERVER_NAME })
    'deathmatch'        = $deathmatch
    'coop'              = $coop
    'dmflags'           = $Env:QUAKE2_DMFLAGS
    'fraglimit'         = $Env:QUAKE2_FRAG_LIMIT
    'timelimit'         = $Env:QUAKE2_TIME_LIMIT
    'capturelimit'      = $Env:QUAKE2_CAPTURE_LIMIT
    'skill'             = $Env:QUAKE2_SKILL
    'sv_maplist'        = $(if ($Env:QUAKE2_MAP_LIST) { ConvertTo-Quoted (($Env:QUAKE2_MAP_LIST -split '[\s,;]+' | Where-Object { $_ }) -join ' ') })
    'sv_password'       = $(if ($Env:QUAKE2_PASSWORD) { ConvertTo-Quoted $Env:QUAKE2_PASSWORD })
    'rcon_password'     = $(if ($Env:QUAKE2_RCON_PASSWORD) { ConvertTo-Quoted $Env:QUAKE2_RCON_PASSWORD })
    'allow_download'    = ConvertTo-Bool $Env:QUAKE2_ALLOW_DOWNLOAD
    'sv_downloadserver' = $(if ($Env:QUAKE2_DOWNLOAD_URL) { ConvertTo-Quoted $Env:QUAKE2_DOWNLOAD_URL })
}

$lines = @('// Generated from the QUAKE2_* environment variables on every start, edit server.cfg instead')

# With QUAKE2_MAP set, server.cfg runs first and the QUAKE2_* settings override it. Without it,
# server.cfg runs last so its own map command starts the server after every setting is in place
if ($Env:QUAKE2_MAP) { $lines += 'exec server.cfg' }

# `set`, because the game's cvars (fraglimit, sv_maplist, ...) don't exist until the map loads
foreach ($key in $values.Keys) {
    if ($null -ne $values[$key] -and $values[$key] -ne '') { $lines += "set $key $($values[$key])" }
}

if (-not $Env:QUAKE2_MAP) { $lines += 'exec server.cfg' }

New-Item -ItemType Directory -Path $dir -Force | Out-Null
[System.IO.File]::WriteAllText($file, ($lines -join "`n") + "`n")
# Not -R: a recursive chown through Merged/ would copy every pak up into Overlay/
chown "$($Env:UID):$($Env:GID)" $file

Write-Log "Wrote QUAKE2_* settings to $file"
