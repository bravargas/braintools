# Version: 0.0.1

$script:IncludeEmptyAddresses = $false
$script:results = @()


$bindings = @{}


function Get-SecurityMode {
    param ($binding)

    $securityNode = $binding.SelectSingleNode("security")
    if ($securityNode -and $securityNode.Attributes["mode"]) {
        return $securityNode.Attributes["mode"].Value
    }
    else {
        return "Blank"
    }
}

function Test-CertificateRequirement {
    param ($binding)

    $transportNode = $binding.SelectSingleNode("security/transport")
    $messageNode = $binding.SelectSingleNode("security/message")

    $transportType = if ($transportNode -and $transportNode.Attributes["clientCredentialType"]) {
        $transportNode.Attributes["clientCredentialType"].Value
    }
    else {
        ""
    }

    $messageType = if ($messageNode -and $messageNode.Attributes["clientCredentialType"]) {
        $messageNode.Attributes["clientCredentialType"].Value
    }
    else {
        ""
    }

    return ($transportType -eq "Certificate" -or $messageType -eq "Certificate")
}

function Get-Bindings {
    [CmdletBinding()]
    param (
        [Parameter()]
        $config
    )
    $config.configuration."system.serviceModel".bindings.ChildNodes | ForEach-Object {
        $bindingType = $_.Name
        foreach ($binding in $_.binding) {
            $name = $binding.name
            $securityMode = Get-SecurityMode -binding $binding
            $requiresCert = Test-CertificateRequirement -binding $binding
            $bindings["${bindingType}:${name}"] = [PSCustomObject]@{
                SecurityMode = $securityMode
                RequiresCert = $requiresCert
            }
        }
    }
}

function Invoke-AnalyzeEndpoint {
    param (
        [string]$address,
        [string]$binding,
        [string]$bindingConfig,
        [string]$contract,
        [string]$name,
        [string]$location
    )

    if (-not $script:IncludeEmptyAddresses -and ([string]::IsNullOrWhiteSpace($address))) {
        return
    }

    $bindingKey = "${binding}:${bindingConfig}"
    $bindingData = if ($bindings.ContainsKey($bindingKey)) { $bindings[$bindingKey] } else {
        [PSCustomObject]@{ SecurityMode = "Blank"; RequiresCert = $false }
    }

    $securityMode = $bindingData.SecurityMode
    $requiresCert = $bindingData.RequiresCert
    $type = if ($contract -eq "IMetadataExchange") { "Metadata" } else { "Service" }

    $status = "Inactive or unreachable"
    $statusColor = "Red"

    if ($type -eq "Metadata") {
        $status = "MEX endpoint detected"
        $statusColor = "Yellow"
    }
    elseif ($address -match '^https?://') {
        try {
            $response = Invoke-WebRequest -Uri $address -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $status = "Active (HTTP $($response.StatusCode))"
            $statusColor = "Green"
        }
        catch {
            # Keep status as default
        }
    }

    $securityColor = if ($securityMode -match "None" -or $securityMode -match "Blank") { "Red" } else { "Cyan" }
    $certColor = if ($requiresCert) { "Red" } else { "Gray" }

    # Console output
    Write-Host "------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Address:               " -ForegroundColor Yellow -NoNewline
    Write-Host "$address" -ForegroundColor White    
    Write-Host "Location:              " -ForegroundColor Yellow -NoNewline
    Write-Host "$location" -ForegroundColor Blue
    Write-Host "Type:                  " -ForegroundColor Yellow -NoNewline
    Write-Host "$type" -ForegroundColor Magenta
    Write-Host "Binding:               " -ForegroundColor Yellow -NoNewline
    Write-Host "$binding" -ForegroundColor Cyan
    Write-Host "Binding Config:        " -ForegroundColor Yellow -NoNewline
    Write-Host "$bindingConfig" -ForegroundColor Cyan
    Write-Host "Security Mode:         " -ForegroundColor Yellow -NoNewline
    Write-Host "$securityMode" -ForegroundColor $securityColor
    Write-Host "Requires Certificate:  " -ForegroundColor Yellow -NoNewline
    Write-Host "$(if ($requiresCert) { 'Yes' } else { 'No' })" -ForegroundColor $certColor
    Write-Host "Status:                " -ForegroundColor Yellow -NoNewline
    Write-Host "$status" -ForegroundColor $statusColor
    #Write-Host "------------------------------------------------------------------"
    Write-Host ""

    # Save result
    $script:results += [PSCustomObject]@{
        Address             = $address        
        Location            = $location
        Type                = $type
        Binding             = $binding
        BindingConfig       = $bindingConfig
        SecurityMode        = $securityMode
        RequiresCertificate = if ($requiresCert) { "Yes" } else { "No" }
        Status              = $status
    }
}

function Invoke-AnalyzeEndpoints {
    [CmdletBinding()]
    param (
        [Parameter()]
        $config
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"    
    try {
        foreach ($type in @(
                @{ Endpoints = $config.configuration."system.serviceModel".services.service.endpoint; Location = "Service" },
                @{ Endpoints = $config.configuration."system.serviceModel".client.endpoint; Location = "Client" }
            )) {
            foreach ($endpoint in $type.Endpoints) {
                Invoke-AnalyzeEndpoint -address $endpoint.address `
                    -binding $endpoint.binding `
                    -bindingConfig $endpoint.bindingConfiguration `
                    -contract $endpoint.contract `
                    -name $endpoint.name `
                    -location $type.Location
            }
        }
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }

}

function Export-Results {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $hostname = $env:COMPUTERNAME
    $safeHost = $hostname -replace '[^a-zA-Z0-9_-]', '_'  # Por si acaso, limpiamos caracteres especiales

    $csvPath = "endpoints_summary_${safeHost}_$timestamp.csv"
    $jsonPath = "endpoints_summary_${safeHost}_$timestamp.json"

    $script:results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    #$script:results | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonPath -Encoding UTF8

    Write-Host "Summary saved to $csvPath and $jsonPath" -ForegroundColor Green
}


function Get-ConfigFilePath {
    param (
        [string]$InitialConfigFilePath
    )

    Add-Type -AssemblyName System.Windows.Forms

    if (-not $InitialConfigFilePath -or -not (Test-Path -Path $InitialConfigFilePath)) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Cannot continue without a valid configuration file. Do you want to browse for the file?",
            "Configuration File Missing",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.InitialDirectory = $PSScriptRoot
            $openFileDialog.Filter = "Configuration files (*.config)|*.config|XML files (*.xml)|*.xml|All files (*.*)|*.*"
            $openFileDialog.Multiselect = $false

            $dialogResult = $openFileDialog.ShowDialog()

            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
                $ConfigFilePath = $openFileDialog.FileName
                Write-Host "Selected configuration file: $ConfigFilePath"
                return $ConfigFilePath
            }
            else {
                Write-Host "No file selected. Exiting script."
                exit
            }
        }
        else {
            Write-Host "User chose not to browse for a file. Exiting script."
            exit
        }
    }
    else {
        Write-Verbose "Configuration file found: $InitialConfigFilePath"
        return $InitialConfigFilePath
    }
}


function Test-Endpoints {
    [CmdletBinding()]
    param ($ConfigFilePath)  

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
    try {
        
        $ConfigFilePath = Get-ConfigFilePath -InitialConfigFilePath $ConfigFilePath
        [xml]$config = Get-Content -Path $ConfigFilePath
        Get-Bindings -config $config
        Invoke-AnalyzeEndpoints -config $config
        Export-Results
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }   

}
