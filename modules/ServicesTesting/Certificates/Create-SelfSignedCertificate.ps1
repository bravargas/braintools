$certName = "localhost"
$pfxFile = "certificate.pfx"
$pfxPassword = ConvertTo-SecureString -String "Abcd1234$" -Force -AsPlainText

# Create the self-signed certificate in the Current User store
$cert = New-SelfSignedCertificate `
    -DnsName $certName `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -NotAfter (Get-Date).AddYears(5) `
    -FriendlyName "Localhost Dev Cert" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256

# Export to PFX file
Export-PfxCertificate `
    -Cert $cert `
    -FilePath $pfxFile `
    -Password $pfxPassword

Write-Host "`n✅ Certificate exported to: $pfxFile"
