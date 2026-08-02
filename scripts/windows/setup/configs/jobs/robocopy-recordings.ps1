#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Source = "${env:USERPROFILE}\Videos",
    [string]$Destination = ($env:NAS_RECORDINGS_PATH ?? "\\truenas-scale\Recordings")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ShouldProcess($Destination, "Robocopy /MIR from $Source")) {
    $arguments = @(
        $Source,
        $Destination,
        '/MIR',
        '/R:2',
        '/W:5',
        '/FFT',
        '/Z',
        '/XA:SH'
    )

    & robocopy @arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) {
        throw "Robocopy failed with exit code $exitCode"
    }
}
