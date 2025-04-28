# Version: 0.0.1

$script:IncludeEmptyAddresses = $true
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
        [string]$serviceName,
        [string]$binding,
        [string]$bindingConfig,
        [string]$contract,
        [string]$name,
        [string]$location,
        [string]$behavior
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
    elseif ($address -eq "") {    
        $address = "N/A"
        $status = "N/A"
        $statusColor = "Gray"
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
    Write-Host "------------------------------------------------------------------------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Address:               " -ForegroundColor Yellow -NoNewline
    Write-Host "$address" -ForegroundColor White    
    Write-Host "Service Name:              " -ForegroundColor Yellow -NoNewline
    Write-Host "$serViceName" -ForegroundColor Magenta
    Write-Host "Location:              " -ForegroundColor Yellow -NoNewline
    Write-Host "$location" -ForegroundColor White
    Write-Host "Type:                  " -ForegroundColor Yellow -NoNewline
    Write-Host "$type" -ForegroundColor Magenta
    Write-Host "Contract:              " -ForegroundColor Yellow -NoNewline
    Write-Host "$contract" -ForegroundColor Magenta
    Write-Host "Binding:               " -ForegroundColor Yellow -NoNewline
    Write-Host "$binding" -ForegroundColor Cyan
    Write-Host "Binding Config:        " -ForegroundColor Yellow -NoNewline
    Write-Host "$bindingConfig" -ForegroundColor Cyan
    Write-Host "Behavior:              " -ForegroundColor Yellow -NoNewline
    Write-Host "$behavior" -ForegroundColor White
    Write-Host "Security Mode:         " -ForegroundColor Yellow -NoNewline
    Write-Host "$securityMode" -ForegroundColor $securityColor
    Write-Host "Requires Certificate:  " -ForegroundColor Yellow -NoNewline
    Write-Host "$(if ($requiresCert) { 'Yes' } else { 'No' })" -ForegroundColor $certColor
    Write-Host "Status:                " -ForegroundColor Yellow -NoNewline
    Write-Host "$status" -ForegroundColor $statusColor
    #Write-Host "------------------------------------------------------------------------------------------------------------------------------------"
    Write-Host ""

    # Save result
    $script:results += [PSCustomObject]@{
        Address             = $address        
        ServiceName         = $serviceName
        Name                = $name
        Location            = $location
        Type                = $type
        Contract            = $contract
        Binding             = $binding
        BindingConfig       = $bindingConfig
        Behavior            = $behavior
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
        $itemCount = 0
        foreach ($type in @(
                @{ Locations = $config.configuration."system.serviceModel".services.service; Location = "Service" },
                @{ Locations = $config.configuration."system.serviceModel".client; Location = "Client" }
            )) {
            foreach ($location in $type.Locations) {
                $ServiceName = if ($type.Location -eq "Service") { $locationname} else { "N/A" } # Only the services have a name
                foreach ($endpoint in $location.endpoint) {
                    itemCount++
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing endpoint $itemCount in $($type.Location)" -ForegroundColor Green
                    Invoke-AnalyzeEndpoint -address $endpoint.address `
                        -ServiceName $ServiceName
                        -binding $endpoint.binding `
                        -bindingConfig $endpoint.bindingConfiguration `
                        -contract $endpoint.contract `
                        -name $endpoint.name `
                        -location $type.Location `
                        -behavior $endpoint.behaviorConfiguration
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

Function Export-Results {
    [CmdletBinding()]
    param (
    	[Parameter()]
    	$ConfigFilePath
    )
    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
    try {
        if (-not $script:results) {
            Write-Host "$($MyInvocation.MyCommand.Name):: No results to export." -ForegroundColor Yellow
            return
        }
    
        # Export results to CSV and JSON
        $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
        $hostname = $env:COMPUTERNAME
        $safehost = $hostname -replace '[^a-zA-Z0-9_-]', '_' # Por si acaso, limpiamos caracteres especiales
    
        $resultsPath = Join-Path -Path $PSScriptRoot -ChildPath "results"
        if (-not (Test-Path $resultsPath)) {
            New-Item -Path $resultsPath -ItemType Directory | Out-Null
        }
    
        Write-Host "Exporting results from $configFilePath to $resultsPath" -ForegroundColor Green
        Write-Host
    
        $csvPath = Join-Path -Path $resultsPath -ChildPath "endpoints_summary_${safehost}_$timestamp.csv"
        $jsonPath = Join-Path -Path $resultsPath -ChildPath "endpoints_summary_${safehost}_$timestamp.json"
    
        $script:results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        $script:results | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonPath -Encoding UTF8
    
        Write-Host "Summary saved to $csvPath and $jsonPath" -ForegroundColor Green
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Get-ConfigFilePath {
    param (
        [string]$InitialConfigFilePath
    )

    Add-Type -AssemblyName System.Windows.Forms

    if (-not $InitialConfigFilePath -or -not (Test-Path -Path $InitialConfigFilePath)) {
        Write-Host "Configuration file not found or not provided. Prompting user to select a file." -ForegroundColor Yellow
        
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
        Write-Verbose "Configuration file found: $InitialConfigFilePath"
        return $InitialConfigFilePath
    }
}


function Test-Endpoints {
    [CmdletBinding()]
    param ($ConfigFilePath)  

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
    try {

        $script:results = @()
        
        $ConfigFilePath = Get-ConfigFilePath -InitialConfigFilePath $ConfigFilePath
        if (-not $ConfigFilePath) {
            Write-Host "No configuration file provided. Exiting script."
            return
        }
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Configuration file: $ConfigFilePath"
        [xml]$config = Get-Content -Path $ConfigFilePath
        Get-Bindings -config $config
        Invoke-AnalyzeEndpoints -config $config
        Export-Results -ConfigFilePath $ConfigFilePath
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }   

}
