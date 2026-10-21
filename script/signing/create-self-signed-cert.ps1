# Creates a self-signed code signing certificate for personal Windows builds.
#
# Run once on the Windows machine you want to trust the builds on:
#
#   powershell -ExecutionPolicy Bypass -File script\signing\create-self-signed-cert.ps1
#
# It writes the .pfx, a base64 copy of it (for the SIGNING_PFX_BASE64 repo
# secret), and the .cer, then trusts the .cer for the current user so Windows
# stops reporting "Unknown publisher" for builds signed with it.
#
# No administrator rights are required: everything lands in Cert:\CurrentUser.

[CmdletBinding()]
Param(
    [string]$Subject = "CN=Zed Personal Build",
    [string]$OutDir = (Join-Path $PSScriptRoot "..\..\signing-out"),
    [string]$Password
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ([string]::IsNullOrWhiteSpace($Password)) {
    $bytes = New-Object byte[] 24
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $Password = [Convert]::ToBase64String($bytes)
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "Creating self-signed code signing certificate for '$Subject'..."
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -CertStoreLocation Cert:\CurrentUser\My `
    -KeyExportPolicy Exportable `
    -KeyLength 3072 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(5)

$pfxPath = Join-Path $OutDir "zed-personal.pfx"
$cerPath = Join-Path $OutDir "zed-personal.cer"
$base64Path = Join-Path $OutDir "pfx.base64.txt"
$securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePassword | Out-Null
Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

# Trust the certificate for the current user: the root store makes the chain
# verifiable, the publisher store removes the "Unknown publisher" prompt.
Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null

[Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath)) | Set-Content -Path $base64Path -NoNewline

Write-Host ""
Write-Host "Done."
Write-Host "  Certificate : $($cert.Thumbprint)"
Write-Host "  PFX         : $pfxPath"
Write-Host "  CER         : $cerPath"
Write-Host "  Base64      : $base64Path"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Repo Settings -> Secrets and variables -> Actions -> New repository secret"
Write-Host "     SIGNING_PFX_BASE64   = contents of $base64Path"
Write-Host "     SIGNING_PFX_PASSWORD = $Password"
Write-Host "  2. Re-run the 'package-windows' workflow; the installer will be signed."
Write-Host ""
Write-Host "Keep the .pfx and its password together: anyone holding them can sign"
Write-Host "code that your machine trusts."
