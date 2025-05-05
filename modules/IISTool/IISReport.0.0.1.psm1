function Get-IISReportCore {
    [CmdletBinding()]
    param (
        [int]$ExpireWarningDays = 30
    )

    Import-Module WebAdministration
    $report = @()
    $now = Get-Date
    $websites = Get-Website

    foreach ($site in $websites) {
        $siteName = $site.Name
        $siteAppPoolName = $site.applicationPool
        $bindings = Get-WebBinding -Name $siteName

        $siteAppPool = Get-Item "IIS:\AppPools\$siteAppPoolName"
        $siteAppPoolInfo = @{
            Name         = $siteAppPoolName
            Status       = (Get-WebAppPoolState -Name $siteAppPoolName).Value
            CLRVersion   = $siteAppPool.managedRuntimeVersion
            PipelineMode = $siteAppPool.managedPipelineMode
            Identity     = $siteAppPool.processModel.identityType
        }

        $webApps = Get-WebApplication -Site $siteName
        $webAppsInfo = @()
        foreach ($app in $webApps) {
            $appPoolName = $app.applicationPool
            $appPool = Get-Item "IIS:\AppPools\$appPoolName"
            $webAppsInfo += @{
                Path        = $app.Path
                AppPoolInfo = @{
                    Name         = $appPoolName
                    Status       = (Get-WebAppPoolState -Name $appPoolName).Value
                    CLRVersion   = $appPool.managedRuntimeVersion
                    PipelineMode = $appPool.managedPipelineMode
                    Identity     = $appPool.processModel.identityType
                }
            }
        }

        foreach ($binding in $bindings) {
            $port = ""
            if ($binding.bindingInformation -match ":(\d+):?$") {
                $port = $matches[1]
            }

            $record = [PSCustomObject]@{
                Website           = $siteName
                BindingInfo       = $binding.bindingInformation
                Protocol          = $binding.protocol
                Port              = $port
                Hostname          = $binding.HostHeader
                CertificateCN     = ''
                CertificateExp    = ''
                CertificateStatus = ''
                SiteAppPool       = $siteAppPoolInfo
                WebAppsInfo       = $webAppsInfo
            }

            if ($binding.protocol -eq 'https') {
                $certHash = $binding.certificateHash
                $certStoreName = $binding.certificateStoreName
                if ($certHash) {
                    $cert = Get-ChildItem "Cert:\LocalMachine\$certStoreName" | Where-Object {
                        $_.Thumbprint -eq $certHash
                    }
                    if ($cert) {
                        $record.CertificateCN = $cert.Subject
                        $record.CertificateExp = $cert.NotAfter

                        if ($cert.NotAfter -lt $now) {
                            $record.CertificateStatus = "Expired"
                        }
                        elseif ($cert.NotAfter -lt $now.AddDays($ExpireWarningDays)) {
                            $record.CertificateStatus = "ExpiringSoon"
                        }
                        else {
                            $record.CertificateStatus = "Valid"
                        }
                    }
                }
            }

            $report += $record
        }
    }

    return $report
}

function Invoke-IISReport {
    param (
        [switch]$AsHtml,
        [switch]$Show,
        [int]$ExpireWarningDays = 30
    )

    $OutputFolder = Join-Path -Path $PSScriptRoot -ChildPath "reports"
    if (-not (Test-Path $OutputFolder)) {
        New-Item -Path $OutputFolder -ItemType Directory | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $report = Get-IISReportCore -ExpireWarningDays $ExpireWarningDays

    $csvPath = Join-Path $OutputFolder "IIS_Report_$timestamp.csv"
    $jsonPath = Join-Path $OutputFolder "IIS_Report_$timestamp.json"
    $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    $report | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8

    Write-Host "Reports generated:"
    Write-Host " - CSV:  $csvPath"
    Write-Host " - JSON: $jsonPath"

    if ($AsHtml) {
        Format-IISReportFlatView -Report $report -AsHtml -OutputPath (Join-Path $OutputFolder "IIS_Report_$timestamp.html")
    }

    if ($Show) {
        Format-IISReportFlatView -Report $report
    }

    return $report
}

function Format-IISReportFlatView {
    param (
        [Parameter(Mandatory)]
        [array]$Report,
        [string]$OutputPath,
        [switch]$AsHtml
    )

    $display = $Report | ForEach-Object {
        [PSCustomObject]@{
            Website           = $_.Website
            Protocol          = $_.Protocol
            Port              = $_.Port
            CertificateCN     = $_.CertificateCN
            CertificateExp    = $_.CertificateExp
            CertificateStatus = $_.CertificateStatus
            SiteAppPool       = $_.SiteAppPool.Name
            SitePoolStatus    = $_.SiteAppPool.Status
            WebAppPaths       = ($_.WebAppsInfo | ForEach-Object { $_.Path }) -join ", "
            WebAppPools       = ($_.WebAppsInfo | ForEach-Object { $_.AppPoolInfo.Name }) -join ", "
        }
    }

    if ($AsHtml -and $OutputPath) {
        $html = @()
        $html += "<!DOCTYPE html><html><head><meta charset='UTF-8'><title>IIS Report</title>"
        $html += "<style>body{font-family:Segoe UI,Tahoma,Arial;}table{border-collapse:collapse;width:100%;}"
        $html += "th,td{border:1px solid #ccc;padding:8px;text-align:left;}th{background:#eee;}"
        $html += ".expired{background:#fdd;color:#900;font-weight:bold;}"
        $html += ".expiring{background:#fff3cd;color:#856404;font-weight:bold;}"
        $html += "</style></head><body><h1>IIS Report (Flat View)</h1><table><thead><tr>"

        $columns = $display[0].PSObject.Properties.Name
        foreach ($col in $columns) { $html += "<th>$col</th>" }
        $html += "</tr></thead><tbody>"

        foreach ($row in $display) {
            $html += "<tr>"
            foreach ($col in $columns) {
                $value = $row.$col
                $class = ""
                if ($col -eq "CertificateStatus") {
                    if ($value -eq "Expired") { $class = " class='expired'" }
                    elseif ($value -eq "ExpiringSoon") { $class = " class='expiring'" }
                }
                $html += "<td$class>$value</td>"
            }
            $html += "</tr>"
        }

        $html += "</tbody></table></body></html>"
        Set-Content -Path $OutputPath -Value $html -Encoding UTF8
        Write-Host " - HTML: $OutputPath"
    }
    else {
        $display | Out-GridView -Title "IIS Report (Flat View)"
    }
}