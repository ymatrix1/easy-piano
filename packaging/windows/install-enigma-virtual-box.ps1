param(
  [Parameter(Mandatory = $true)]
  [string] $Destination
)

$ErrorActionPreference = 'Stop'
$url = 'https://enigmaprotector.com/assets/files/enigmavb.exe'
$expectedSha256 = 'AB743F5E3DD927A288E126BBB053D367F270592E89378C9A06B7F3B15FA1EE35'
$installer = Join-Path $env:RUNNER_TEMP 'enigmavb-11.30.exe'

Invoke-WebRequest -Uri $url -OutFile $installer
$actualSha256 = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
if ($actualSha256 -ne $expectedSha256) {
  throw "Enigma Virtual Box checksum mismatch. Expected $expectedSha256; received $actualSha256."
}

$signature = Get-AuthenticodeSignature -FilePath $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*enigmaprotector.com*') {
  throw 'Enigma Virtual Box installer did not have a valid signature from its publisher.'
}

$arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$Destination`""
$process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
if ($process.ExitCode -ne 0) {
  throw "Enigma Virtual Box installer failed with exit code $($process.ExitCode)."
}

$console = Join-Path $Destination 'enigmavbconsole.exe'
if (-not (Test-Path -LiteralPath $console)) {
  throw "Enigma Virtual Box console was not installed at $console."
}

Write-Output "Installed Enigma Virtual Box 11.30 at $Destination"
