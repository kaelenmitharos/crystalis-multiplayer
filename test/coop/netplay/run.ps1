# Same-PC RetroArch netplay test for the co-op ROM (Windows PowerShell).
#
#   .\run.ps1 -RetroArch C:\path\to\RetroArch-Win64 -Rom C:\path\to\crystalis-coop-v0.1.nes
#             [-Core mesen|fceumm] [-Minutes 15]
#
# Starts a host and a client RetroArch on 127.0.0.1 (each with its own
# config, save folder and core options in a temporary folder), runs
# netplay_soak.js against them, then closes both.  Needs Node.js and the
# core in <RetroArch>\cores.  Exit code 0 = all checks passed.
param(
  [Parameter(Mandatory = $true)][string]$RetroArch,
  [Parameter(Mandatory = $true)][string]$Rom,
  [string]$Core = "mesen",
  [int]$Minutes = 15
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path ([IO.Path]::GetTempPath()) "coop-netplay-$PID"
$exe = Join-Path $RetroArch "retroarch.exe"
$dll = Join-Path $RetroArch "cores\${Core}_libretro.dll"
if (-not (Test-Path $exe)) { throw "no retroarch.exe in $RetroArch" }
if (-not (Test-Path $dll)) { throw "no $Core core in $RetroArch\cores" }

function Write-Config($who, $cmdPort, $padPort) {
  $dir = Join-Path $work $who
  New-Item -ItemType Directory -Force (Join-Path $dir "saves"), (Join-Path $dir "states") | Out-Null
  # Sprite limit off, no overclock (the defaults otherwise).
  @(
    'mesen_nospritelimit = "enabled"', 'mesen_overclock = "None"',
    'fceumm_nospritelimit = "enabled"', 'fceumm_overclocking = "disabled"'
  ) | Set-Content -Encoding ascii (Join-Path $dir "core.opt")
  @(
    "libretro_directory = `"$RetroArch\cores`"",
    "libretro_info_path = `"$RetroArch\info`"",
    "system_directory = `"$dir`"",
    "savefile_directory = `"$dir\saves`"",
    "savestate_directory = `"$dir\states`"",
    "core_options_path = `"$dir\core.opt`"",
    'global_core_options = "true"',
    'config_save_on_exit = "false"',
    'pause_nonactive = "false"',
    'audio_mute_enable = "true"',
    'video_fullscreen = "false"',
    'menu_driver = "rgui"',
    'network_cmd_enable = "true"',
    "network_cmd_port = `"$cmdPort`"",
    'network_remote_enable = "true"',
    "network_remote_base_port = `"$padPort`"",
    'network_remote_enable_user_p1 = "true"',
    "netplay_nickname = `"$who`"",
    'netplay_check_frames = "0"'
  ) | Set-Content -Encoding ascii (Join-Path $dir "retroarch.cfg")
  return $dir
}

$hostDir = Write-Config "host" 55355 55400
$clientDir = Write-Config "client" 55356 55500
$romArg = "`"$Rom`""
$dllArg = "`"$dll`""
$h = Start-Process -FilePath $exe -WorkingDirectory $RetroArch -PassThru -ArgumentList @(
  "--config", "`"$hostDir\retroarch.cfg`"", "-L", $dllArg, $romArg,
  "--host", "--port", "55435", "--verbose", "--log-file", "`"$hostDir\retroarch.log`"")
Start-Sleep -Seconds 3
$c = Start-Process -FilePath $exe -WorkingDirectory $RetroArch -PassThru -ArgumentList @(
  "--config", "`"$clientDir\retroarch.cfg`"", "-L", $dllArg, $romArg,
  "--connect", "127.0.0.1", "--port", "55435", "--verbose", "--log-file", "`"$clientDir\retroarch.log`"")
Start-Sleep -Seconds 5
try {
  node (Join-Path $here "netplay_soak.js") $Minutes
  $code = $LASTEXITCODE
} finally {
  Stop-Process -Id $c.Id -Force -ErrorAction SilentlyContinue
  Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue
}
Get-Content "$hostDir\retroarch.log", "$clientDir\retroarch.log" |
  Select-String -Pattern "joined as|Disconnect" | ForEach-Object { $_.Line }
Write-Output "logs and configs: $work"
exit $code
