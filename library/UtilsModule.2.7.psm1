# Creator: Brainer Vargas
# Email: brainer.vargasrojas@fiserv.com
# Created: 2024-08-01
# Last modification: 2025-04-02
# Version: 2.6


# Function to check connectivity for a single URL
function CheckConnectivity($url) {
    Write-Host "-----------------------------"
    Write-Host "$url"

    if ($ignoreList -contains $url) {
        $message = "URL ignored. URL: $url"
        Write-Host $message -ForegroundColor Cyan
        return
    }

    try {
        $uri = New-Object System.Uri($url)
        $hostname = $uri.Host
        $port = $uri.Port

        ##$tcpClient = [System.Net.Sockets.TcpClient]::New()
        $tcpClient = New-Object -TypeName System.Net.Sockets.TcpClient

        $connectTask = $tcpClient.ConnectAsync($hostname, $port).Wait($timeoutMilliseconds)

        if ($tcpClient.Connected) {
            $message = "TCP Client: Connection successful to Host: $hostname $port"
            Write-Host $message -ForegroundColor Green
        }
        else {
            $message = "TCP Client: Failed to establish connection to Host: $hostname $port"
            Write-Host $message  -ForegroundColor Yellow
        }
        if ($retryTest) {
            $message = "Trying with Test-NetConnection"
            Write-Host $message  -ForegroundColor Yellow

            $result = Test-NetConnection -ComputerName $hostname -Port $port -InformationLevel Detailed

            if ($result) {
        
                if ($result.TcpTestSucceeded) {
                    $message = "Connection successful! URL: $url"
                    Write-Host $message -ForegroundColor Green
                }
                else {
                    $message = "Tcp Test Failed. URL: $url"
                    Write-Host $message -ForegroundColor Yellow
                }
                Write-Host "Test-NetConnection Result:"
                Write-Host "Destination Host Name: $($result.ComputerName)"
                Write-Host "IP Address: $($result.RemoteAddress.IPAddressToString)"
                Write-Host "Port: $($result.RemotePort)"
                Write-Host "TcpTestSucceeded: $($result.TcpTestSucceeded)"

            }
            else {
                $message = "Test-NetConnection returned an error. URL: $url"
                Write-Host $message -ForegroundColor Yellow
            }
        }
        
    }
    catch {
        $message = "Exception triggered. Failed to establish connection. Error: $($_.Exception.Message)"
        Write-Host $message -ForegroundColor Yellow
    }

}

# Function to validate a URL
function Test-Url {
    param (
        [Parameter(Mandatory = $true)]
        [string]$url
    )

    $urlPattern = '^((https?|ftp)://)?([a-zA-Z0-9]+([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+|www\.[a-zA-Z0-9]+(\.[a-zA-Z]{2,})?)(:\d{1,5})?(/.*)?$'

    if ($url -match $urlPattern) {
        return $true
    }
    else {
        return $false
    }
}

function Get-Certificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('FriendlyName', 'SerialNumber', 'Thumbprint', 'PfxCertificateAndPwd', 'Subject')]
        [string]$SearchBy,
        [Parameter(Mandatory = $true)]
        [string]$SearchValue,
        [string]$Store
    )
    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        Write-Verbose "Search by: $SearchBy"
        Write-Verbose "Value: $SearchValue"
     
        if ($SearchBy -eq 'PfxCertificateAndPwd') {
            # Split the combined credential into filename and password
            $fileName, $Password = $SearchValue -split '\|' 
    
            # Load the certificate from the file using the combined credential
            $certificatePath = "$fileName"
            Write-Host "$($MyInvocation.MyCommand.Name):: Looking for $certificatePath"
    
            try {
                if (Test-Path -Path $certificatePath) {
                    $certificates = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificatePath, $Password)
                }
                else {
                    throw "The file: $certificatePath does not exist."
                }
                if ($certificates.Count -eq 0) {
                    Write-Host "$($MyInvocation.MyCommand.Name):: No matching certificates found." -ForegroundColor Red
                    return $null
                }                
            }
            catch {
                Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred while loading the certificate:`n$($_.Exception.Message)"
            }
        }
        else {
            # Set the default store location if not provided
            if (-not $Store) {
                $Store = 'LocalMachine\My'
            }
    
            # Call Find-Certificate with the appropriate search criteria
            $certificates = Get-ChildItem -Path "Cert:\$Store" | Where-Object {
                $_.$SearchBy -like "*$SearchValue*"
            }
    
            if ($certificates.Count -eq 0) {
                Write-Host "$($MyInvocation.MyCommand.Name):: No matching certificates found." -ForegroundColor Red
                return $null
            }
   
        }
        Write-Host "$($MyInvocation.MyCommand.Name):: Certificate found" -ForegroundColor Green
        return $certificates[0]             
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred while searching for the certificate:`n$($_.Exception.Message)"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }    

}


# Global variables to hold session ID and log file name
$script:Session = $null
$script:LogFilePath = $null

function Initialize-Logger {
    [CmdletBinding()]        
    param (
        [string]$LogFilePath,
        [string]$Session
    )

    Write-Verbose "START $($MyInvocation.MyCommand.Name)"
    # Set the global session ID and log file name
    # Check if $Session is provided and set $script:Session accordingly
    if ($Session) {
        $script:Session = $Session
    }
    else {
        $script:Session = [guid]::NewGuid().ToString()
    }
    $script:LogFilePath = $LogFilePath

    # Output the session ID for verification
    Write-Verbose "Logger Session ID: $script:Session"
    Write-Verbose "Logger file path: $script:LogFilePath"
        
    Write-Verbose "END $($MyInvocation.MyCommand.Name)"
}
function Write-Log {
    [CmdletBinding()]        
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]        
        [string]$LogLevel = "INFO",
        [string]$Caller,
        [Parameter(Mandatory = $false)]
        [switch]$LogOnly,
        [Parameter(Mandatory = $false)]
        [switch]$Checkmark,
        [Parameter(Mandatory = $false)]
        [switch]$NoNewline,                
        [Parameter(Mandatory = $false)]
        [ValidateSet('Yellow', 'Green', 'Red', 'Blue', 'Magenta', 'Cyan', 'White', 'DarkYellow', 'DarkGreen', 'DarkRed', 'DarkBlue', 'DarkMagenta', 'DarkCyan', 'Gray', 'DarkGray', 'NoColor')]
        [string]$ForegroundColor,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Black', 'DarkGray', 'White', 'Gray')]
        [string]$BackgroundColor,
        [switch]$ShowCaller    
    )

    if (-not($Caller)) {
        $CallStack = Get-PSCallStack
        $Caller = if ($CallStack.Count -gt 1) {
            $CallStack[1].FunctionName
        }
        else {
            "<Direct Call or ScriptBlock>"
        }
    }

    $CheckmarkChar = [char]0x221A
    if ($Checkmark) {
        $Message = "$CheckmarkChar $Message"
    }

    if ($script:LogFilePath) {
        # Capture additional information (timestamp, machine name, etc.)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $logEntry = "$env:COMPUTERNAME`t$timestamp`t$LogLevel`t$Caller`t$script:Session`t$Message"
    
        # Append to a log file
        if (-not (Test-Path -Path $script:LogFilePath)) {
            "Machine`tTime`tType`tCaller`tSession`tDescription" | Out-File -Append -FilePath $script:LogFilePath
        }
        
        $logEntry | Out-File -Append -FilePath $script:LogFilePath

    }
    else {
        Write-Host "Cannot create log entries without a file. Try running: Initialize-Logger -LogFilePath $LogFileName -Session $GlobalSession"
    }

   
    if ($LogOnly) {
        return #Don't show the message in the console, only in the log file
    }

    if ($ShowCaller) {
        $Message = "$Caller :: $Message"
    }

    # Output to console (like Write-Host)
    # Write message to console with specified color and background color (if specified)
    if ($ForegroundColor -and $BackgroundColor) {
        Write-Host -NoNewline -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor $Message
    }
    elseif ($ForegroundColor) {
        Write-Host -NoNewline -ForegroundColor $ForegroundColor $Message
    }
    elseif ($BackgroundColor) {
        Write-Host -NoNewline -BackgroundColor $BackgroundColor $Message
    }
    else {
        Write-Host -NoNewline $Message
    }

    # Write newline character if NoNewline switch is not specified
    if (!$NoNewline) {
        Write-Host ""
    }

}

function Submit-RestRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url, # The base URL for the REST API call

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$RequestContent, # The request content (already processed with placeholders replaced)

        [Parameter(Mandatory = $false)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null, # Optional certificate for authentication

        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json"  # Content type for the request
    )

    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"

        # Store the original callback
        $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback

        # Combine the base URL and the action to form the full URI
        $fullUrl = "$Url/$($RequestContent.Action)"
        
        # Prepare headers
        $headers = @{}
        if ($RequestContent.Headers) {
            # Convert the headers to a hashtable
            $headers = @{}
            foreach ($key in $RequestContent.Headers.PSObject.Properties.Name) {
                $headers[$key] = $RequestContent.Headers.$key
            }
        }
        $headers["Content-Type"] = $ContentType

        try {
        # Prepare the request parameters
        $requestParams = @{
            Uri     = $fullUrl
            Method  = $RequestContent.Method
            Headers = $headers
        }

        # Add the body if provided
        if ($RequestContent.PSObject.Properties.Name -contains 'Body') {
            $requestParams.Body = $RequestContent.Body | ConvertTo-Json -Depth 10
        }

        # Add the certificate if provided
        if ($Certificate) {
            $requestParams.Certificate = $Certificate
        }

        # Execute the REST API call
        $response = Invoke-WebRequest @requestParams -UseBasicParsing
        }
        catch {
            if ($_.Exception.Message -like "*SSL/TLS*") {
                Write-Warning "Initial request failed due to SSL error. Ignoring SSL errors and retrying..."
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                $response = Invoke-WebRequest @requestParams -UseBasicParsing
            }
            else {
                Write-Host "Error: $($_)" -ForegroundColor Red            
                throw $_
            }
            
        }

        # Convert the response content to JSON if applicable
<#         if ($response.Content) {
            return $response.Content | ConvertFrom-Json
        } #>

        return $response
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    finally {
        # Revert to the original callback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }
}

function Submit-SOAPRequest {
    [CmdletBinding()]        
    param (
        [string]$Url,
        [xml]$RequestContent,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$certificate,
        [string]$ContentType = "text/xml; charset=utf-8"
    )

    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
    
        # Store the original callback
        $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback

        # Extract the Action
        $action = $RequestContent.MessageLogTraceRecord.Envelope.Header.Action.'#text' 
        
        # Remove the Header node
        if ($ContentType -eq "text/xml; charset=utf-8") {
            # Check if the Action element exists before removing it
            if ($null -ne $RequestContent.MessageLogTraceRecord.Envelope.Header.Action) {
                [void]$RequestContent.MessageLogTraceRecord.Envelope.Header.RemoveChild($RequestContent.MessageLogTraceRecord.Envelope.Header.Action)
            }

            # Check if the To element exists before removing it
            if ($null -ne $RequestContent.MessageLogTraceRecord.Envelope.Header.To) {
                [void]$RequestContent.MessageLogTraceRecord.Envelope.Header.RemoveChild($RequestContent.MessageLogTraceRecord.Envelope.Header.To)
            }

        }
     
        # Extract the Envelope
        $soapEnvelope = $RequestContent.MessageLogTraceRecord.Envelope.OuterXml 
        $headers = @{'SOAPAction' = $action; 'Content-Type' = $ContentType }        
        
        try {
            $requestParams = @{Uri = $url; Method = 'POST' }
            #$requestParams.add("ContentType", $headers['Content-Type'])
            $requestParams.add("Headers", $headers)
            $requestParams.add("Body", $soapEnvelope)
            if ($certificate) {
                $requestParams.add("Certificate", $certificate)
            }
            $response = Invoke-WebRequest @requestParams -UseBasicParsing
        }
        catch {
            if ($_.Exception.Message -like "*SSL/TLS*") {
                Write-Warning "Initial request failed due to SSL error. Ignoring SSL errors and retrying..."
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                $response = Invoke-WebRequest @requestParams -UseBasicParsing
            }
            else {
                Write-Host "Error: $($_)" -ForegroundColor Red            
                throw $_
            }
            
        }
        if ($response) {
            # Display the beautified XML response content
            $xmlDocument = New-Object System.Xml.XmlDocument
            $xmlDocument.LoadXml($response.Content)
            return $xmlDocument
        }            
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        # Revert to the original callback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback        
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }

}

function Start-RestRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url, # The base URL for the REST API call

        [Parameter(Mandatory = $true)]
        [string]$RequestFilePath, # Path to the JSON request file

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings, # Hashtable containing placeholder values

        [Parameter(Mandatory = $true)]
        [hashtable]$AdditionalParams, # Additional parameters for placeholder replacement

        [Parameter(Mandatory = $false)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null, # Optional certificate for authentication

        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json"  # Content type for the request
    )

    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"

        # Merge settings, additional parameters, and ContentType into placeholders
        $placeholders = $Settings + $AdditionalParams
        $placeholders["ContentType"] = $ContentType

        # Update the JSON file with placeholder values
        $modifiedJson = Update-JsonValues -JsonFilePath $RequestFilePath -PlaceholderValues $placeholders

        # Call Submit-RestRequest with the updated JSON content
        $response = Submit-RestRequest -Url $Url -RequestContent $modifiedJson -Certificate $Certificate -ContentType $ContentType

        # Return the response
        return $response
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }
}

function Start-SOAPRequest {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Url,
        [Parameter()]
        [string]$RequestFilePath,
        [Parameter()]
        [hashtable]$Settings,
        [Parameter()]
        [hashtable]$AdditionalParams,
        [Parameter()]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null,
        [string]$ContentType = "text/xml; charset=utf-8"
    )
    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"

        # Merge settings and additional parameters
        $placeholders = $Settings + $AdditionalParams

        # Handle certificate if needed
        if (-not $Certificate -and $Settings.ContainsKey('CertificateSerialNumber')) {
            $Certificate = Get-Certificate -SearchBy 'SerialNumber' -SearchValue $Settings['CertificateSerialNumber'] -Store 'LocalMachine\My'
        }

        # Set XML placeholders
        $modifiedXml = Update-XmlValues -XmlFilePath $RequestFilePath -PlaceholderValues $placeholders    
        #$safeXml = Update-XmlValues -XmlFilePath $RequestFilePath -PlaceholderValues  @{Password = '******'} 

        #Write-Host $(Format-XML $modifiedXml.OuterXml -indent 4) -ForegroundColor Gray
        Write-Verbose $(Format-XML $modifiedXml.OuterXml -indent 4)

        # Send SOAP request
        $xmlResponse = Submit-SOAPRequest -Url $Url -RequestContent $modifiedXml -certificate $Certificate -ContentType $ContentType

        # Check if the response is not null
        if ($null -ne $xmlResponse) {        
            # Return the relevant part of the response
            if ($xmlResponse -and $xmlResponse.Envelope -and $xmlResponse.Envelope.Body) {
                # Display the XML response
                #Write-Host $(Format-XML $xmlResponse.OuterXml -indent 4) -ForegroundColor Green
                $FormattedResponse = $(Format-XML $xmlResponse.OuterXml -indent 4)
                Write-Verbose $FormattedResponse
                return $xmlResponse.Envelope.Body
            }
            else {
                return $xmlResponse
            }
        }
    }

    catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"            
    }    
}
function Set-XMLPlaceholders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$XmlFilePath,
 
        [Parameter(Mandatory = $true, Position = 1)]
        [hashtable]$PlaceholderValues
    )
 
    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        # Load the XML content as an XML object
        [xml]$xmlContent = Get-Content -Path $XmlFilePath -Raw
 
        # Convert the XML object to a string for easy manipulation
        $xmlString = $xmlContent.OuterXml
 
        # Iterate over each placeholder in the hashtable and replace it in the XML string
        foreach ($key in $PlaceholderValues.Keys) {
            $placeholder = "{{" + $key + "}}"
            $value = $PlaceholderValues[$key]
            $xmlString = $xmlString -replace [regex]::Escape($placeholder), $value
        }
 
        # Convert the modified string back to an XML object
        [xml]$modifiedXml = $xmlString
 
        # Return the modified XML object
        return $modifiedXml
 
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"            
    }
}

function Update-JsonValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$JsonFilePath,

        [Parameter(Mandatory = $true, Position = 1)]
        [hashtable]$PlaceholderValues
    )

    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"

        # Load the JSON content as a string
        $jsonContent = Get-Content -Path $JsonFilePath -Raw

        # Iterate over each placeholder in the hashtable and replace it in the JSON string
        foreach ($key in $PlaceholderValues.Keys) {
            $placeholder = "{" + $key + "}"
            $value = $PlaceholderValues[$key]
            $jsonContent = $jsonContent -replace [regex]::Escape($placeholder), $value
        }

        # Convert the modified JSON string back to a JSON object
        $modifiedJson = $jsonContent | ConvertFrom-Json

        # Return the modified JSON object
        return $modifiedJson
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }
}

function Update-XmlValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$XmlFilePath,
 
        [Parameter(Mandatory = $true, Position = 1)]
        [hashtable]$PlaceholderValues
    )
 
    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        # Load the XML content as an XML object
        [xml]$xmlContent = Get-Content -Path $XmlFilePath -Raw
 
        # Iterate over each placeholder in the hashtable and replace it in the XML string
        foreach ($key in $PlaceholderValues.Keys) {
            $value = $PlaceholderValues[$key]
            $xmlContent.SelectNodes("//*[local-name()='$key']") | ForEach-Object {
                $_.InnerText = $value            
            }
        }
        # Return the modified XML object
        return $xmlContent
 
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"            
    }
}

function Read-ConfigurationDetails {
    [CmdletBinding()]
    param (
        [string]$ParametersFilePath,
        [string]$Name
    )

    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        Write-Verbose "ParametersFilePath: $ParametersFilePath"
        Write-Verbose "Name: $Name"
       
        # Load the Parameters from the XML file
        [xml]$parametersXml = Get-Content -Path $ParametersFilePath
        $Parameters = @{}
        foreach ($node in $parametersXml.config.parameters.ChildNodes) {
            $Parameters[$node.Name] = $node.InnerText
        }

        # Extract SystemConfigFileName from Parameters
        $SystemConfigFileName = $Parameters['SystemConfigFileName']
        if (-not $SystemConfigFileName) {
            Throw "SystemConfigFileName not specified in parameters file"
        }

        # Construct the path to the system config file
        $ParametersFolderPath = Split-Path -Path $ParametersFilePath
        $SystemConfigFilePath = Join-Path -Path $ParametersFolderPath -ChildPath $SystemConfigFileName

        Write-Verbose "SystemConfigFilePath: $SystemConfigFilePath"

        # Read the system config file
        if (Test-Path -Path $SystemConfigFilePath) {
            # Load the XML file
            [xml]$xml = Get-Content -Path $SystemConfigFilePath
            # Select the Proxy node with name '$Name'
            $Proxy = $xml.Configuration.Environment.BankingInterfaces.Proxy | Where-Object { $_.name -eq "$Name" }

            # Replace placeholders with actual Parameters
            foreach ($property in $Proxy.Property) {
                if ($property.value -match '\$\{\w+\}') {
                    $property.value = [regex]::Replace($property.value, '\$\{(\w+)\}', { param($match) $Parameters[$match.Groups[1].Value] })
                }
            }

            # Assign each property value to a variable using a hashtable for easier access
            $properties = @{}
            foreach ($property in $Proxy.Property) {
                $properties[$property.key] = $property.value
            }

            return $properties
        }
        else {
            Throw "Unable to find system configuration file: $SystemConfigFilePath"
        }              
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }
}

function Read-MachineConfigurationDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MachineName,
        [Parameter(Mandatory = $true)]
        [string]$ParametersFilePath,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        Write-Verbose "ParametersFilePath: $ParametersFilePath"
        Write-Verbose "MachineName: $MachineName"
        Write-Verbose "Name: $Name"

        # Load the Parameters from the XML file
        [xml]$parametersXml = Get-Content -Path $ParametersFilePath
        $Parameters = @{}

        # Extract shared parameters
        foreach ($node in $parametersXml.config.parameters.ChildNodes) {
            if ($node.Name -ne "machineConfig") {
                $Parameters[$node.Name] = $node.InnerText
            }
        }

        # Extract machine-specific parameters
        $machineNode = $parametersXml.config.parameters.machineConfig.machine | Where-Object {
            $_.name -eq $MachineName
        }
        if (-not $machineNode) {
            Throw "Machine configuration for '$MachineName' not found in the parameters file."
        }

        # Add machine-specific parameters
        foreach ($node in $machineNode.ChildNodes) {
            $Parameters[$node.Name] = $node.InnerText
        }

        # Add the targetenvironment to the parameters
        $Parameters["TargetEnvironment"] = $machineNode.targetenvironment

        # Extract SystemConfigFileName from Parameters
        $SystemConfigFileName = $Parameters['SystemConfigFileName']
        if (-not $SystemConfigFileName) {
            Throw "SystemConfigFileName not specified in parameters file."
        }

        # Construct the path to the system config file
        $ParametersFolderPath = Split-Path -Path $ParametersFilePath
        $SystemConfigFilePath = Join-Path -Path $ParametersFolderPath -ChildPath $SystemConfigFileName

        Write-Verbose "SystemConfigFilePath: $SystemConfigFilePath"

        # Read the system config file
        if (Test-Path -Path $SystemConfigFilePath) {
            # Load the XML file
            [xml]$xml = Get-Content -Path $SystemConfigFilePath
            # Select the Proxy node with name '$Name'
            $Proxy = $xml.Configuration.Environment.BankingInterfaces.Proxy | Where-Object { $_.name -eq "$Name" }

            # Replace placeholders with actual Parameters
            foreach ($property in $Proxy.Property) {
                if ($property.value -match '\$\{\w+\}') {
                    $property.value = [regex]::Replace($property.value, '\$\{(\w+)\}', { param($match) $Parameters[$match.Groups[1].Value] })
                }
            }

            # Assign each property value to a variable using a hashtable for easier access
            $properties = @{}
            foreach ($property in $Proxy.Property) {
                $properties[$property.key] = $property.value
            }

            # Merge shared and machine-specific parameters with system config properties
            foreach ($key in $Parameters.Keys) {
                $properties[$key] = $Parameters[$key]
            }

            return $properties
        }
        else {
            Throw "Unable to find system configuration file: $SystemConfigFilePath"
        }
    }
    catch {
        Write-Error "An error occurred: $_"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }
}

function Format-XML ([xml]$xml, $indent = 2) {
    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        $StringWriter = New-Object System.IO.StringWriter
        $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter
        $xmlWriter.Formatting = "indented"
        $xmlWriter.Indentation = $Indent
        $xml.WriteContentTo($XmlWriter)
        $XmlWriter.Flush()
        $StringWriter.Flush()

        return $StringWriter.ToString()
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }        
    
}

function Get-CertificateDetails {
    [CmdletBinding()]
    param (
        [ValidateSet('Issued_To', 'Issued_By', 'Expiration_Date', 'Friendly_Name', 'Serial_Number', 'Thumbprint')]
        [string]$OrderBy,
        [ValidateSet('LocalMachine\My', 'CurrentUser\My')]
        [string]$Store = 'LocalMachine\My'
    )

    $certificates = Get-ChildItem -Path Cert:\$Store
    $certificateList = @()

    foreach ($cert in $certificates) {
        $HasPrivateKey = $false
        $UsersWithAccess = ''
        if ($cert.HasPrivateKey) {        
            $HasPrivateKey = $true
            $usersWithAccess = Get-PrivateKeyUsers -Certificate $cert
            if ($UsersWithAccess) {
                Write-Debug "Users with access: $UsersWithAccess"
            }
        }
        $subjectCN = $cert.Subject.Split(",")[0] -replace "CN=", "" -replace "OU=", ""
        $issuerCN = $cert.Issuer.Split(",")[0] -replace "CN=", "" -replace "OU=", ""

        $certificateObject = New-Object PSObject -Property @{
            'Issued_To'         = $subjectCN
            'Issued_By'         = $issuerCN
            'Expiration_Date'   = $cert.NotAfter
            'Friendly_Name'     = $cert.FriendlyName
            'Serial_Number'     = $cert.SerialNumber
            'Thumbprint'        = $cert.Thumbprint
            'Has_Private_Key'   = $HasPrivateKey
            'Users_With_Access' = $UsersWithAccess
        }
        $certificateList += $certificateObject
    }

    return $certificateList | Select-Object 'Issued_To', 'Issued_By', 'Expiration_Date', 'Friendly_Name', 'Serial_Number', 'Thumbprint', 'Has_Private_Key', 'Users_With_Access' | Sort-Object $OrderBy

    # Example usage:
    #Get-CertificateDetails -OrderBy Issued_To -Store LocalMachine\My | Select-Object 'Issued_To', 'Issued_By','Expiration_Date', 'Friendly_Name', 'Serial_Number', 'Thumbprint','Has_Private_Key', 'Users_With_Access' | Where-Object Users_With_Access -Like '*svc_QACOL12*' | Sort-Object 'Issued_To'

}

function Get-PrivateKeyUsers {
    [CmdletBinding()]
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$FileSystemRights = 'FullControl'
    )

    $keypath = "$($env:ProgramData)\Microsoft\Crypto\RSA\MachineKeys\"
    $privkey = $Certificate.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
    $privkeypath = (Get-Item "$keypath\$privkey")

    # Get the ACL and extract the access list
    $acl = Get-Acl $privKeyPath
    $privateKeyUsers = $acl.Access |
    Where-Object { $_.AccessControlType -eq 'Allow' -and $_.FileSystemRights -like "*$FileSystemRights*" } |
    Select-Object -ExpandProperty IdentityReference |
    ForEach-Object { $_.Value }

    return $privateKeyUsers -join ', '
}

function Show-MenuLegacy {
    [CmdletBinding()]
    param (
        [string]$Title,
        [string[]]$Options,
        [string[]]$Header
    )

    Write-Verbose "START $($MyInvocation.MyCommand.Name)"


    $TitleSpaces = " " * 5
    # Find the length of the longest string
    $HeaderMaxLength = $Header | ForEach-Object { $_.Length } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
    $OptionsMaxLength = $Options | ForEach-Object { $_.Length } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    
    $OptionsSeparator = ". "
    $OptionsSpaces = " " * 8
    $ItemMaxLength = $OptionsMaxLength + $Options.Length.ToString().Length + $OptionsSeparator.Length + $OptionsSpaces.Length
    $TitleMaxLength = $TitleSpaces.Length + $Title.Length

    # Compare the lengths and assign the largest one to a variable
    $SeparatorLength = if ($HeaderMaxLength -gt $ItemMaxLength) { $HeaderMaxLength } else { $ItemMaxLength }
    $SeparatorLength = if ($SeparatorLength -gt $TitleMaxLength) { $SeparatorLength } else { $TitleMaxLength }
    

    if ($Header)	{
        # Print the Header
        Write-Host ("-" * $SeparatorLength)
        for ($i = 0; $i -lt $Header.Length; $i++) {
            Write-Host "$($Header[$i])" -ForegroundColor Cyan
        }		
    }

    # Print the title
    Write-Host ("-" * $SeparatorLength)
    Write-Host "$TitleSpaces$Title"
    Write-Host ("-" * $SeparatorLength)

    # Print the options
    for ($i = 0; $i -lt $Options.Length; $i++) {
        if ($i -le 9) {
            <# Action to perform if the condition is true #>
        }  
        #Write-Host "$($OptionsSpaces)$($i + 1)$OptionsSeparator$($Options[$i])"
        Write-Host "$($OptionsSpaces)$('{0:D2}' -f ($i + 1))$OptionsSeparator$($Options[$i])"

    }

    # Print the exit option
    Write-Host "${OptionsSpaces}00. Exit"
    Write-Host " "
    Write-Host ("-" * $SeparatorLength)  	

    Write-Verbose "END $($MyInvocation.MyCommand.Name)"
}

function Show-Menu {
    [CmdletBinding()]
    param (
        [string]$Title,
        [object[]]$Options,
        [string[]]$Header,
        [string]$DividerLine = "---",
        [string]$ExitOption = "Exit"
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        $TitleSpaces = " " * 3

        # Safely extract lengths
        $HeaderMaxLength = ($Header | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $OptionNames = $Options | ForEach-Object {
            if ($_ -is [string]) {
                $_
            } 
            elseif ($_.PSObject.Properties["Name"]) {
                $_.Name
            } 
            else {
                "<unnamed>"
            }
        }
        $OptionsMaxLength = ($OptionNames | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $OptionsSeparator = " $([char]0x2500) "  # ─
        $OptionsSpaces = " " * 4
        $ItemMaxLength = $OptionsMaxLength + $Options.Length.ToString().Length + $OptionsSeparator.Length + $OptionsSpaces.Length
        $TitleMaxLength = $TitleSpaces.Length + $Title.Length

        $SeparatorLength = [int](
            @($HeaderMaxLength, $ItemMaxLength, $TitleMaxLength | Where-Object { $_ -ne $null }) |
            Measure-Object -Maximum |
            Select-Object -ExpandProperty Maximum
        )

        # Box drawing chars
        $TopLeft = [char]0x250C  # ┌
        $TopRight = [char]0x2510  # ┐
        $BottomLeft = [char]0x2514  # └
        $BottomRight = [char]0x2518  # ┘
        $Horizontal = [char]0x2500  # ─
        $Vertical = [char]0x2502  # │
        $Tee = [char]0x252C  # ┬
        $Cross = [char]0x253C  # ┼
        $LeftTee = [char]0x251C  # ├
        $RightTee = [char]0x2524  # ┤

        $TopLine = "$TopLeft" + ("$Horizontal" * $SeparatorLength) + "$TopRight"
        $SplitLine = "$LeftTee" + ("$Horizontal" * $SeparatorLength) + "$RightTee"
        $BottomLine = "$BottomLeft" + ("$Horizontal" * $SeparatorLength) + "$BottomRight"

        $FrameColor = "Gray"

        # Header box
        if ($Header) {
            Write-Host ($TopLine) -ForegroundColor $FrameColor
            foreach ($line in $Header) {
                #Write-Host ("$Vertical" + $line.PadRight($SeparatorLength) + "$Vertical") -ForegroundColor Cyan
                Write-Host ("$Vertical") -NoNewline -ForegroundColor $FrameColor
                Write-Host ($line.PadRight($SeparatorLength)) -NoNewline -ForegroundColor Cyan
                Write-Host ("$Vertical") -ForegroundColor $FrameColor
            }
            Write-Host ($SplitLine) -ForegroundColor $FrameColor
        }

        # Title
        Write-Host ("$Vertical") -NoNewline -ForegroundColor $FrameColor
        Write-Host (($TitleSpaces + $Title).PadRight($SeparatorLength)) -NoNewline -ForegroundColor Yellow
        Write-Host ("$Vertical") -ForegroundColor $FrameColor
        Write-Host ($SplitLine) -ForegroundColor $FrameColor

        # Menu items
        $item = 0
        for ($i = 0; $i -lt $Options.Length; $i++) {
            $displayName = if ($Options[$i] -is [string]) {
                $Options[$i]
            } 
            else {
                "<unnamed>"
            }

            $item++
            if ($displayName -eq $DividerLine) {
                Write-Host ($SplitLine) -ForegroundColor $FrameColor
                $item--
            }
            else {
                $optionText = "$OptionsSpaces$('{0:D2}' -f ($item))$OptionsSeparator$displayName"
                Write-Host ("$Vertical") -NoNewline -ForegroundColor $FrameColor
                Write-Host ($optionText.PadRight($SeparatorLength)) -NoNewline -ForegroundColor White
                Write-Host ("$Vertical") -ForegroundColor $FrameColor
            }
        }

        # Exit (no quotes)
        $exitText = "$OptionsSpaces" + "00$OptionsSeparator" + $ExitOption
        Write-Host ("$Vertical") -NoNewline -ForegroundColor $FrameColor
        Write-Host ($exitText.PadRight($SeparatorLength)) -NoNewline -ForegroundColor Red
        Write-Host ("$Vertical") -ForegroundColor $FrameColor        
        

        # Footer
        Write-Host ($BottomLine) -ForegroundColor $FrameColor
    }
    catch {
        Write-Error "Error in $($MyInvocation.MyCommand.Name): $_"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}
function Get-UserChoice {
    [CmdletBinding()]
    param (
        [int]$MaxOption
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        while ($true) {
            $choice = Read-Host "Please enter your choice (0-$MaxOption)"
            if ($choice -match '^\d+$' -and [int]$choice -ge 0 -and [int]$choice -le $MaxOption) {
                return [int]$choice
            }
            else {
                Write-Host "Invalid choice. Please enter a number between 0 and $MaxOption." -ForegroundColor Red
            }
        }
    }
    catch {
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Open-SQLConnection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$connectionString
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        return $connection
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Close-SQLConnection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$connection
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        
        if ($connection.State -eq 'Open') {
            $connection.Close()
        }
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Get-SqlData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$query
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        
        $command = $global:connection.CreateCommand()
        $command.CommandText = $query

        $dataTable = New-Object System.Data.DataTable
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        
        $adapter.Fill($dataTable) | Out-Null

        return $dataTable
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Export-ToCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Array]$dataTable,
        [Parameter(Mandatory = $true)]
        [string]$outputFilePath,
        [char]$delimiter = "`t"
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        
        $csvOutput = $dataTable | ConvertTo-Csv -Delimiter $delimiter -NoTypeInformation
        $csvOutput | Out-File -FilePath $outputFilePath -Encoding UTF8
        
        Write-Verbose "`nCSV file created successfully at:"
        Write-Verbose "$outputFilePath `n"
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Show-DataTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Array]$DataTable,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Table", "GridView")]
        [string]$DisplayMode
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        
        # Display the result based on the DisplayMode parameter
        if ($DisplayMode -eq "Table") {
            $DataTable | Format-Table -AutoSize
        }
        elseif ($DisplayMode -eq "GridView") {
            $DataTable | Out-GridView -Title $Title
        }
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Get-TagValues {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$tags
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        
        $tagValues = @{}
        foreach ($tag in $tags) {
            $tagName = $tag.Trim('{', '}')
            $value = Read-Host "Enter the value for $tagName"
            $tagValues[$tag] = $value
        }

        return $tagValues
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Show-Progress {
    [CmdletBinding()]
    param (
        [string]$activity,
        [string]$status
    )
    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
    for ($i = 0; $i -le 100; $i += 10) {
        Write-Progress -Activity $activity -Status $status -PercentComplete $i
        Start-Sleep -Seconds 1
    }
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}

function Rename-HashtableKeys {
    [CmdletBinding()]
    param (
        [hashtable]$OriginalHashtable,
        [hashtable]$KeyMappings
    )
    try {
        Write-Verbose "START $($MyInvocation.MyCommand.Name)"
        # Create a new hashtable with renamed keys
        $newHashtable = @{}

        # Copy values from the original hashtable to the new one with renamed keys
        foreach ($key in $OriginalHashtable.Keys) {
            if ($KeyMappings.ContainsKey($key)) {
                $newHashtable[$KeyMappings[$key]] = $OriginalHashtable[$key]
            }
            else {
                $newHashtable[$key] = $OriginalHashtable[$key]
            }
        }

        return $newHashtable
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred while Renaming the Hashtable Keys:`n$($_.Exception.Message)"
    }
    finally {
        Write-Verbose "END $($MyInvocation.MyCommand.Name)"
    }

}

function Get-ConfigValues {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$XPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigFilePath
    )
    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        [xml]$config = Get-Content -Path $ConfigFilePath
        $nodes = $config.SelectNodes($XPath)
        $values = @()
        foreach ($node in $nodes) {
            if ($node -is [System.Xml.XmlAttribute]) {
                $values += $node.Value
            }
            else {
                $values += $node.InnerText
            }
        }
        return $values
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

#Export-ModuleMember -Function Initialize-Logger, Write-Log, Get-Certificate, Test-Url, Set-XMLPlaceholders, Read-ConfigurationDetails, Format-XML, Get-UserChoice, Show-Menu, Rename-HashtableKeys, Open-SQLConnection, Close-SQLConnection, Get-SqlData, Export-ToCSV, Show-DataTable, Get-TagValues, Show-Progress, Get-ConfigValues,Start-SOAPRequest, Submit-SOAPRequest, Read-MachineConfigurationDetails
Export-ModuleMember -Function Initialize-Logger, Write-Log, Get-Certificate, Test-Url, Set-XMLPlaceholders, Read-ConfigurationDetails, Format-XML, Get-UserChoice, Show-MenuLegacy, Rename-HashtableKeys, Open-SQLConnection, Close-SQLConnection, Get-SqlData, Export-ToCSV, Show-DataTable, Get-TagValues, Show-Progress, Get-ConfigValues, Start-SOAPRequest, Submit-SOAPRequest, Read-MachineConfigurationDetails, CheckConnectivity, Get-CertificateDetails, Get-PrivateKeyUsers, Start-RestRequest, Submit-RestRequest, Update-JsonValues, Update-XmlValues, Show-Menu