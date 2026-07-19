#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$NetCfg,
    [switch]$ReleaseRenew,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Error 'This script must be run as Administrator.'
    exit 1
}

if (-not $Force) {
    Write-Host 'This will reset your Windows network stack and require a reboot.' -ForegroundColor Yellow
    if ($NetCfg) {
        Write-Host 'WARNING: -NetCfg will delete ALL network adapters and revert everything to factory.' -ForegroundColor Red
    }
    $reply = Read-Host 'Continue? [y/N]'
    if ($reply -notmatch '^(y|yes)$') {
        Write-Host 'Cancelled.' -ForegroundColor Cyan
        exit 0
    }
}

$commands = @(
    @{Cmd = 'ipconfig'; Args = @('/flushdns'); Desc = 'Flush DNS cache' }
)

if ($ReleaseRenew) {
    $commands += @{Cmd = 'ipconfig'; Args = @('/release'); Desc = 'Release DHCP lease' }
    $commands += @{Cmd = 'ipconfig'; Args = @('/renew'); Desc = 'Renew DHCP lease' }
}

$commands += @(
    @{Cmd = 'netsh'; Args = @('int', 'ip', 'reset'); Desc = 'Reset TCP/IP stack (requires reboot)' }
    @{Cmd = 'netsh'; Args = @('winsock', 'reset'); Desc = 'Reset Winsock catalog (requires reboot)' }
)

if ($NetCfg) {
    $commands += @{Cmd = 'netcfg'; Args = @('-d'); Desc = 'Reset all network adapters to factory (requires reboot)' }
}

$exitCode = 0
foreach ($item in $commands) {
    $desc = $item.Desc
    Write-Host "[*] $desc..." -ForegroundColor Cyan

    if ($PSCmdlet.ShouldProcess($desc, 'Run command')) {
        try {
            $output = & $item.Cmd $item.Args 2>&1
            $output | ForEach-Object { Write-Host ("    $_") }
        } catch {
            Write-Host "    FAILED: $_" -ForegroundColor Red
            $exitCode = 1
        }
    } else {
        Write-Host "    (dry run) $($item.Cmd) $($item.Args -join ' ')" -ForegroundColor DarkGray
    }
}

Write-Host 'Reset complete. A reboot is required for changes to take effect.' -ForegroundColor Green
exit $exitCode
