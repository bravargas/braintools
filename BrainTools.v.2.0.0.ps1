[CmdletBinding()]
param (
    [string]$Environment = "MOCK", # Default to "QA"
    [string[]]$RequestFiles = $null # Optional parameter for specifying one or more request files
)


# Change directory to $PSScriptRoot at the start of the script
Set-Location -Path $PSScriptRoot

# Global parameters array
$Global:Parameters = @{}

# If request files are provided, execute them in order and terminate the script
if ($RequestFiles) {
    try {
        foreach ($RequestFile in $RequestFiles) {
            Write-Host "Executing request file: $RequestFile" -ForegroundColor Cyan

            # Process the specified request file
            $processedContent = Invoke-RequestFile -FilePath $RequestFile

            # Invoke the request
            $response = Invoke-Request -RequestContent $processedContent.RequestContent -Certificate $processedContent.Certificate -ProxyUrl $processedContent.ProxyUrl -ProxyUsername $processedContent.ProxyUsername -ProxyPassword $processedContent.ProxyPassword

            # Process the response
            if ($response) {
                Invoke-ProcessResponse -ResponseContent $response -RequestTemplate $processedContent.RequestContent
            }

            Write-Host "Request execution completed for: $RequestFile" -ForegroundColor Green
        }
    } catch {
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    } finally {
        exit
    }
}

# Centralized error logging function
function Write-ErrorLog {
    param (
        [string]$FunctionName,
        [string]$ErrorMessage
    )
    Write-Host "$FunctionName:: An error occurred: $ErrorMessage" -ForegroundColor Red
}

# Centralized configuration paths
function Get-ConfigPath {
    param (
        [string]$ConfigName
    )

    switch ($ConfigName) {
        "Hosts" { return "$PSScriptRoot\Config\parameters.$($Environment.ToLower()).json" }
        "Menu" { return "$PSScriptRoot\Config\MenuConfig.ps1" }
        default { throw "Unknown configuration name: $ConfigName" }
    }
}

# Helper function to check if a file exists
function Test-FileExists {
    param (
        [string]$FilePath
    )

    if (-not (Test-Path -Path $FilePath)) {
        throw "File not found: $FilePath"
    }
}

# Helper function to resolve placeholders
function Resolve-Placeholders {
    param (
        [string]$Content,
        [hashtable]$ResolvedPlaceholders
    )

    foreach ($key in $ResolvedPlaceholders.Keys) {
        $escapedKey = [regex]::Escape($key)
        $Content = $Content -replace "{{\s*$escapedKey\s*}}", $ResolvedPlaceholders[$key]
    }

    return $Content
}

# Standardized error handling
function Resolve-Error {
    param (
        [string]$FunctionName,
        [string]$ErrorMessage
    )

    Write-Host "$FunctionName:: An error occurred: $ErrorMessage" -ForegroundColor Red
}

function Show-Menu {
    [CmdletBinding()]
    param (
        [string]$Title,
        [object[]]$Options,
        [string[]]$Header
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        $TitleSpaces = " " * 3

        # Safely extract lengths
        $HeaderMaxLength = ($Header | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $OptionNames = $Options | ForEach-Object {
            if ($_ -is [string]) {
                $_
            } elseif ($_.PSObject.Properties["Name"]) {
                $_.Name
            } else {
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
        $TopLeft     = [char]0x250C  # ┌
        $TopRight    = [char]0x2510  # ┐
        $BottomLeft  = [char]0x2514  # └
        $BottomRight = [char]0x2518  # ┘
        $Horizontal  = [char]0x2500  # ─
        $Vertical    = [char]0x2502  # │
        $Tee         = [char]0x252C  # ┬
        $Cross       = [char]0x253C  # ┼
        $LeftTee    = [char]0x251C  # ├
        $RightTee   = [char]0x2524  # ┤

        $FrameColor = "Gray"

        # Header box
        if ($Header) {
            Write-Host ("$TopLeft" + ("$Horizontal" * $SeparatorLength) + "$TopRight") -ForegroundColor $FrameColor
            foreach ($line in $Header) {
                Write-Host ("$Vertical" + $line.PadRight($SeparatorLength) + "$Vertical") -ForegroundColor Cyan
            }
            Write-Host ("$LeftTee" + ("$Horizontal" * $SeparatorLength) + "$RightTee") -ForegroundColor $FrameColor
        }

        # Title
        Write-Host ("$Vertical" + ($TitleSpaces + $Title).PadRight($SeparatorLength) + "$Vertical") -ForegroundColor Yellow
        Write-Host ("$LeftTee" + ("$Horizontal" * $SeparatorLength) + "$RightTee") -ForegroundColor $FrameColor

        # Menu items
        for ($i = 0; $i -lt $Options.Length; $i++) {
            $displayName = if ($Options[$i] -is [string]) {
                $Options[$i]
            } elseif ($Options[$i].PSObject.Properties["Name"]) {
                $Options[$i].Name
            } else {
                "<unnamed>"
            }

            $optionText = "$OptionsSpaces$('{0:D2}' -f ($i + 1))$OptionsSeparator$displayName"
            Write-Host ("$Vertical" + $optionText.PadRight($SeparatorLength) + "$Vertical") -ForegroundColor White
        }

        # Exit (no quotes)
        $exitText = "$OptionsSpaces" + "00$OptionsSeparator" + "Exit"
        Write-Host ("$Vertical" + $exitText.PadRight($SeparatorLength) + "$Vertical") -ForegroundColor Red

        # Footer
        Write-Host ("$BottomLeft" + ("$Horizontal" * $SeparatorLength) + "$BottomRight") -ForegroundColor $FrameColor
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

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        # Validate PfxCertificateAndPwd format
        if ($SearchBy -eq 'PfxCertificateAndPwd' -and $SearchValue -notmatch '.+\|.+') {
            throw "Invalid format for PfxCertificateAndPwd. Expected 'filename|password'."
        }

        if ($SearchBy -eq 'PfxCertificateAndPwd') {
            # Split the combined credential into filename and password
            $fileName, $Password = $SearchValue -split '\|' 

            # Load the certificate from the file using the combined credential
            $certificatePath = "$fileName"

            try {
                if (Test-Path -Path $certificatePath) {
                    $fullCertificatePath = Resolve-Path -Path $certificatePath | Select-Object -ExpandProperty Path
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Looking for $fullCertificatePath"                    
                    $certificates = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($fullCertificatePath, $Password)
                }
                else {
                    throw "$($MyInvocation.MyCommand.Name):: The file: $certificatePath does not exist."
                }
                if ($certificates.Count -eq 0) {
                    Write-Host "$($MyInvocation.MyCommand.Name):: No matching certificates found." -ForegroundColor Red
                    return $null
                }                
            }
            catch {
                Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
            }
        }
        else {
            # Set the default store location if not provided. Consider to use CurrentUser\My instead
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
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Invoke-RequestFile {
    [CmdletBinding()]
    param (
        [string]$FilePath
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        # Check if the request file exists
        Test-FileExists -FilePath $FilePath

        # Load the request file content once
        $requestContent = Get-Content -Path $FilePath -Raw
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Loaded request file: $FilePath"

        # Load the hosts configuration
        $hostsFilePath = Get-ConfigPath -ConfigName "Hosts"
        Test-FileExists -FilePath $hostsFilePath
        $hostsConfig = Get-Content -Path $hostsFilePath | ConvertFrom-Json
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Loaded hosts file: $hostsFilePath"

        # Extract placeholders
        $placeholders = ([regex]::Matches($requestContent, '{{(.*?)}}') | ForEach-Object { $_.Groups[1].Value }).Trim()
        $resolvedPlaceholders = @{}

        # Include global request parameters
        if ($hostsConfig.GlobalRequestParameters) {
            foreach ($key in $hostsConfig.GlobalRequestParameters.PSObject.Properties.Name) {
                $resolvedPlaceholders[$key] = $hostsConfig.GlobalRequestParameters.$key
            }
        }

        # Initialize optional parameters for Invoke-Request
        $certificate = $null
        $proxyUrl = $null
        $proxyUsername = $null
        $proxyPassword = $null

        foreach ($placeholder in $placeholders) {
            $placeholderName = $placeholder.Trim('{}')

            if ($placeholderName.StartsWith('$')) {
                # Handle special placeholders with $
                switch ($placeholderName) {
                    '$GUID' { $resolvedPlaceholders[$placeholderName] = [guid]::NewGuid().ToString() }
                    '$TimeStamp' { $resolvedPlaceholders[$placeholderName] = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }
                    '$IP' { $resolvedPlaceholders[$placeholderName] = (Get-NetIPAddress -AddressFamily IPv4 | Select-Object -First 1 -ExpandProperty IPAddress) }
                    default { throw "Unknown special placeholder: $placeholderName" }
                }
            }
            elseif ($placeholderName.StartsWith('#')) {
                # Handle host placeholders with #
                $hostKey = $placeholderName.TrimStart('#')
                if (-not $hostsConfig.Hosts.PSObject.Properties[$hostKey]) {
                    throw "Host placeholder '$placeholderName' not found in hosts file."
                }
                $resolvedPlaceholders[$placeholderName] = $hostsConfig.Hosts.$hostKey.host

                # Handle certificate if required
                if ($hostsConfig.Hosts.$hostKey.UseCertificate -and $hostsConfig.Hosts.$hostKey.UseCertificate.enabled) {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Certificate required for host '$hostKey'. Fetching certificate..."
                    $certificate = Get-Certificate -SearchBy $hostsConfig.Hosts.$hostKey.UseCertificate.SearchBy -SearchValue $hostsConfig.Hosts.$hostKey.UseCertificate.SearchValue -Store $hostsConfig.Hosts.$hostKey.UseCertificate.Store
                    if (-not $certificate) {
                        throw "Failed to retrieve the required certificate for host '$hostKey'."
                    }
                }

                # Handle proxy if required
                if ($hostsConfig.Hosts.$hostKey.UseProxy -and $hostsConfig.Hosts.$hostKey.UseProxy.enabled) {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Proxy required for host '$hostKey'. Configuring proxy..."
                    $proxyUrl = $hostsConfig.Hosts.$hostKey.UseProxy.proxyUrl
                    $proxyUsername = $hostsConfig.Hosts.$hostKey.UseProxy.proxyUsername
                    $proxyPassword = $hostsConfig.Hosts.$hostKey.UseProxy.proxyPassword
                }
            }
            else {
                # Check if the placeholder exists in GlobalRequestParameters
                if ($resolvedPlaceholders.ContainsKey($placeholderName)) {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Using global parameter for $placeholderName."
                }
                else {
                    # Retrieve the default parameter value from the request file
                    $defaultValue = if ($Global:Parameters.ContainsKey($placeholderName)) { $Global:Parameters[$placeholderName] } else { '' }

                    if ([string]::IsNullOrWhiteSpace($defaultValue)) {
                        $xmlContent = [xml]$requestContent
                        $parametersSection = $xmlContent.SelectSingleNode("//*[local-name()='parameters']")
                        if ($parametersSection) {
                            $parameterNode = $parametersSection.SelectSingleNode("parameter[name='$placeholderName']")
                            if ($parameterNode) {
                                $valueNode = $parameterNode.SelectSingleNode("value")
                                if ($valueNode) {
                                    $defaultValue = $valueNode.InnerText
                                }
                            }
                        }
    
                    }

                    # Prompt the user for input if no default value is found
                    $userInput = Read-Host "Enter the value for $placeholderName (default: $defaultValue)"
                    $resolvedPlaceholders[$placeholderName] = if ([string]::IsNullOrWhiteSpace($userInput)) { $defaultValue } else { $userInput }
                    $Global:Parameters[$placeholderName] = $resolvedPlaceholders[$placeholderName]
                }

                # Update or insert the parameter in the request file
                $null = Update-OrInsertParameter -FilePath $FilePath -ParamName $placeholderName -ParamValue $resolvedPlaceholders[$placeholderName]

            }

        }

        # Replace placeholders in the request content
        $requestContent = Resolve-Placeholders -Content $requestContent -ResolvedPlaceholders $resolvedPlaceholders

        Write-Verbose "$($MyInvocation.MyCommand.Name):: Placeholders resolved and replaced in memory."

        # Return the processed content, certificate, and proxy
        return @{
            RequestContent = [xml]$requestContent
            Certificate    = $certificate
            ProxyUrl       = $proxyUrl
            ProxyUsername  = $proxyUsername
            ProxyPassword  = $proxyPassword
        }
    }
    catch {
        Resolve-Error -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}
function Invoke-Request {
    [CmdletBinding()]
    param (
        [xml]$RequestContent,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null,
        [string]$ProxyUrl = $null,
        [string]$ProxyUsername = $null,
        [string]$ProxyPassword = $null
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        # Extract required fields from the XML
        $type = $RequestContent.requestTemplate.type
        $method = $RequestContent.requestTemplate.method

        $uri = $RequestContent.requestTemplate.url + $RequestContent.requestTemplate.path

        $headers = @{}
        foreach ($header in $RequestContent.requestTemplate.headers.header) {
            $headers[$header.name] = $header.value
        }
        $body = if ($null -ne $RequestContent.requestTemplate.body) {
            if ($type -eq "SOAP") {
                $RequestContent.requestTemplate.body.InnerXml
            }
            else {
                $RequestContent.requestTemplate.body
            }
        }
        else {
            $null
        }

        # Print the exact request in verbose mode
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Preparing to execute request:"
        Write-Verbose "Method: $method"
        Write-Verbose "URI: $uri"
        Write-Verbose "Headers: $($headers | ConvertTo-Json -Depth 10)"
        Write-Verbose "Body: $body"

        # Prepare parameters for Invoke-WebRequest
        $params = @{
            Uri     = $uri
            Method  = $method
            Headers = $headers
        }
        if ($body) {
            $params.Body = $body
        }
        if ($Certificate) {
            $params.Certificate = $Certificate
        }

        # Handle proxy configuration
        if ($ProxyUrl) {
            $params.Proxy = $ProxyUrl
            if ($ProxyUsername -and $ProxyPassword) {
                $proxyCredential = New-Object System.Management.Automation.PSCredential($ProxyUsername, (ConvertTo-SecureString $ProxyPassword -AsPlainText -Force))
                $params.ProxyCredential = $proxyCredential
            }
        }
     
        # Make the HTTP request using Invoke-WebRequest
        $response = Invoke-WebRequest @params

        # Print the status code
        Write-Host "HTTP Status Code: $($response.StatusCode)" -ForegroundColor Cyan

        # Handle the response based on the request type
        if ($type -eq "REST") {
            # Parse JSON response for REST calls
            $parsedResponse = $response.Content | ConvertFrom-Json
            Write-Verbose "$($MyInvocation.MyCommand.Name):: REST request completed successfully."
            return $parsedResponse
        }
        elseif ($type -eq "SOAP") {
            # Return raw content for SOAP calls
            Write-Verbose "$($MyInvocation.MyCommand.Name):: SOAP request completed successfully."
            return $response.Content
        }
        else {
            throw "Unknown request type: $type. Supported types are REST and SOAP."
        }
    }
    catch {
        Write-Host "An error occurred while executing the request: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function PrettyPrint-Xml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$XmlString, # The XML string to format
        [string]$RootElement = "Root", # Optional root element to wrap the XML
        [int]$Indent = 4 # Optional indentation level
    )

    try {
        # Remove the XML declaration if it exists
        $XmlString = $XmlString -replace '<\?xml.*?\?>', ''

        # Wrap the XML string in a single root element
        $WrappedXmlString = "<$RootElement>$XmlString</$RootElement>"

        # Load the wrapped XML string into an XML object
        [xml]$XmlObject = $WrappedXmlString

        # Create a StringWriter and XmlTextWriter for pretty printing
        $StringWriter = New-Object System.IO.StringWriter
        $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter
        $XmlWriter.Formatting = "Indented"
        $XmlWriter.Indentation = $Indent

        # Write the XML content to the XmlWriter
        $XmlObject.WriteTo($XmlWriter)
        $XmlWriter.Flush()
        $StringWriter.Flush()

        # Return the formatted XML as a string
        return $StringWriter.ToString()
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $XmlString
    }
}

function Format-JsonObject {
    param (
        [Parameter(Mandatory = $true)]
        [Object]$JsonObject
    )

    if ($JsonObject -is [System.Collections.IDictionary]) {
        # Handle dictionaries (objects)
        $formatted = @{ }
        foreach ($key in $JsonObject.Keys) {
            Write-Verbose "Processing key: $key"
            $formatted[$key] = Format-JsonObject -JsonObject $JsonObject[$key]
        }
        return $formatted
    }
    elseif ($JsonObject -is [System.Collections.IEnumerable] -and -not ($JsonObject -is [string])) {
        # Handle arrays
        Write-Verbose "Processing array: $JsonObject"
        return $JsonObject | ForEach-Object { Format-JsonObject -JsonObject $_ }
    }
    else {
        # Handle primitive values
        Write-Verbose "Processing value: $JsonObject"
        return $JsonObject
    }
}

function Invoke-ProcessRestResponse {
    param (
        $ResponseContent,
        $ResponseActions
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing REST response."

    try {
        $parsedResponse = $ResponseContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Response is not valid JSON. Treating as plain string."
        $parsedResponse = $ResponseContent
    }

    foreach ($action in $ResponseActions) {
        $path = $action.path
        $display = $action.display
        $expression = $action.expression
        $globalVariableName = $action.globalVariableName

        if (-not $path) {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Skipping action with no path."
            continue
        }

        $value = $null

        if ($path -eq ".") {
            # Assign the entire response to $value
            $value = $parsedResponse
        }
        elseif ($parsedResponse -is [PSCustomObject]) {
            $nodes = $path -split '\.'
            $currentNode = $parsedResponse

            foreach ($node in $nodes) {
                if ($node -match '^(?<name>.+?)\[(?<index>\d+)\]$') {
                    $nodeName = $matches['name']
                    $nodeIndex = [int]$matches['index']

                    if ($currentNode.PSObject.Properties[$nodeName] -and $currentNode.$nodeName -is [System.Collections.IEnumerable]) {
                        $currentNode = $currentNode.$nodeName[$nodeIndex]
                    }
                    else {
                        Write-Host "Node '$nodeName' is not an array or index '$nodeIndex' is out of range." -ForegroundColor Red
                        $currentNode = $null
                        break
                    }
                }
                else {
                    if ($currentNode.PSObject.Properties[$node]) {
                        $currentNode = $currentNode.$node
                    }
                    else {
                        Write-Host "Node '$node' not found." -ForegroundColor Red
                        $currentNode = $null
                        break
                    }
                }
            }
            if ($expression) {
                $value - Invoke-Expression $expression
            }
            else {
                $value = $currentNode
            }
        }
        else {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Path '$path' is invalid for a plain string response."
        }

        if ($null -ne $value) {
            if ($display -eq "true") {
                Write-Host "Extracted Value ($path): " -ForegroundColor Green
                Write-Host "$($value | ConvertTo-Json -Depth 10)" -ForegroundColor White
            }

            if ($globalVariableName) {
                $Global:Parameters[$globalVariableName] = $value
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Stored value in global variable '$globalVariableName'."
            }
        }
        else {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: No value found for path '$path'."
        }
    }
}

function Invoke-ProcessSoapResponse {
    param (
        $ResponseContent,
        $ResponseActions
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing SOAP response."

    $xmlResponse = New-Object System.Xml.XmlDocument
    $xmlResponse.LoadXml($ResponseContent)

    $responseBody = $xmlResponse.SelectSingleNode("//*[local-name()='Body']")

    foreach ($action in $ResponseActions) {
        $path = $action.path
        $display = $action.display
        $expression = $action.expression
        $globalVariableName = $action.globalVariableName

        if (-not $path) {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Skipping action with no path."
            continue
        }

        # Handle special case for displaying the entire response
        if ($path -eq ".") {
            if ($display -eq "true") {
                Write-Host "Full SOAP Response:" -ForegroundColor Green
                # Format and print the XML content with proper indentation
                Write-Host (PrettyPrint-Xml -XmlString $ResponseContent -Indent 4) -ForegroundColor White
                Write-Host " "
            }

            if ($null -ne $globalVariableName -and $globalVariableName -ne "") {
                $Global:Parameters[$globalVariableName] = $ResponseContent
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Stored full response in global variable '$globalVariableName'."
            }
            continue
        }

        $nodes = $path -split '\.'
        $currentNode = $responseBody

        foreach ($node in $nodes) {
            if ($node -match '^(?<name>.+?)\[(?<index>\d+)\]$') {
                $nodeName = $matches['name']
                $nodeIndex = [int]$matches['index']

                $currentNode = $currentNode.ChildNodes | Where-Object { $_.LocalName -eq $nodeName }
                if ($currentNode.Count -gt $nodeIndex) {
                    $currentNode = $currentNode[$nodeIndex]
                }
                else {
                    Write-Host "Index '$nodeIndex' out of range for node '$nodeName'." -ForegroundColor Red
                    $currentNode = $null
                    break
                }
            }
            else {
                $currentNode = $currentNode.ChildNodes | Where-Object { $_.LocalName -eq $node }
                if ($currentNode.Count -eq 1) {
                    $currentNode = $currentNode
                }
                elseif ($currentNode.Count -eq 0) {
                    Write-Host "Node '$node' not found." -ForegroundColor Red
                    $currentNode = $null
                    break
                }
            }
        }

        if ($currentNode) {
            $value = $currentNode.InnerXml

            if ($expression) {
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Evaluation expression: $expression"
                # Evaluate the expression in the context of the current node
                $value = Invoke-Expression $expression
            }

            if ($display -eq "true") {
                Write-Host "Extracted Value ($path): " -ForegroundColor Green
                # Format and print the XML content with proper indentation
                Write-Host (PrettyPrint-Xml - $value -Indent 4)  -ForegroundColor White
                Write-Host " "
            }

            if ($null -ne $globalVariableName -and $globalVariableName -ne "") {
                $Global:Parameters[$globalVariableName] = $value
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Stored value in global variable '$globalVariableName'."
            }
        }
        else {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: No value found for path '$path'."
        }
    }
}
function Invoke-ProcessResponse {
    [CmdletBinding()]
    param (
        $ResponseContent, # Accept as an object to handle both JSON and XML
        [xml]$RequestTemplate
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        $responseActions = $RequestTemplate.requestTemplate.responseActions.action
        if (-not $responseActions) {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: No response actions defined."
            return
        }

        $responseType = $RequestTemplate.requestTemplate.type

        if ($responseType -eq "REST") {
            Invoke-ProcessRestResponse -ResponseContent $ResponseContent -ResponseActions $responseActions
        }
        elseif ($responseType -eq "SOAP") {
            Invoke-ProcessSoapResponse -ResponseContent $ResponseContent -ResponseActions $responseActions
        }
        else {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Unknown response type detected. Skipping."
        }
    }
    catch {
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Update-OrInsertParameter {
    param (
        [string]$FilePath,
        [string]$ParamName,
        [string]$ParamValue
    )

    try {
        # Resolve the file path relative to $PSScriptRoot
        $ResolvedFilePath = Join-Path -Path $PSScriptRoot -ChildPath $FilePath

        # Check if the file exists
        if (-not (Test-Path -Path $ResolvedFilePath)) {
            throw "File not found: $ResolvedFilePath"
        }

        # Load the XML content
        [xml]$xmlContent = Get-Content -Path $ResolvedFilePath -Raw

        # Ensure the <parameters> section exists
        $parametersSection = $xmlContent.SelectSingleNode("//*[local-name()='parameters']")
        if (-not $parametersSection) {
            $parametersSection = $xmlContent.CreateElement("parameters")
            if ($null -ne $xmlContent.DocumentElement) {
                $xmlContent.DocumentElement.AppendChild($parametersSection)
            }
            else {
                throw "The XML document does not have a root element to append the <parameters> section."
            }
        }

        # Check if the parameter already exists
        $parameterNode = $parametersSection.SelectSingleNode("parameter[name='$ParamName']")
        if ($parameterNode) {
            # Update the value if the parameter exists
            $valueNode = $parameterNode.SelectSingleNode("value")
            if ($valueNode) {
                $valueNode.InnerText = $ParamValue
            }
            else {
                # Create a <value> element if it doesn't exist
                $valueNode = $parameterNode.AppendChild($xmlContent.CreateElement("value"))
                $valueNode.InnerText = $ParamValue
            }
        }
        else {
            # If the parameter does not exist, insert it
            $newParameter = $parametersSection.AppendChild($xmlContent.CreateElement("parameter"))
            $nameNode = $newParameter.AppendChild($xmlContent.CreateElement("name"))
            $nameNode.InnerText = $ParamName
            $valueNode = $newParameter.AppendChild($xmlContent.CreateElement("value"))
            $valueNode.InnerText = $ParamValue
        }

        # Save the updated XML back to the file
        $xmlContent.Save($ResolvedFilePath)
        Write-Verbose "Parameter '$ParamName' updated or inserted successfully in $ResolvedFilePath"

        # Retrieve the parameter value for use in the script
        return $valueNode.InnerText
    }
    catch {
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    }
}

try {
    Clear-Host
    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    Set-Location -Path $PSScriptRoot

    # Import the menu configuration
    . (Get-ConfigPath -ConfigName "Menu")

    # Example usage of the Environment parameter
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Using environment: $Environment"

    # Extract the 'Name' property from each option
    $menuOptions = $menuConfig.Options | ForEach-Object { $_.Name }

    # Keep showing the menu until the user selects the exit option
    while ($true) {
        Show-Menu -Title $menuConfig.Title -Options $menuOptions -Header $menuConfig.Header
        $userChoice = Get-UserChoice -MaxOption $menuOptions.Length

        if ($userChoice -eq 0) {
            Write-Host "You chose to exit." -ForegroundColor Green
            break
        }
        else {
            $selectedOption = $menuConfig.Options[$userChoice - 1]
            Write-Host "You selected: $($selectedOption.Name)" -ForegroundColor Cyan
            Write-Host "File Path: $($selectedOption.FilePath)" -ForegroundColor Yellow

            # Process the selected request file
            $processedContent = Invoke-RequestFile -FilePath $selectedOption.FilePath
            Write-Host "Processed Content:" -ForegroundColor Green

            # Format and print the XML content with proper indentation
            Write-Host $(PrettyPrint-Xml -XmlString $processedContent.RequestContent.OuterXml -RootElement "Roor" -indent 4) -ForegroundColor White
            Write-Host " "

            # Invoke the request
            $response = Invoke-Request -RequestContent $processedContent.RequestContent -Certificate $processedContent.Certificate -ProxyUrl $processedContent.ProxyUrl -ProxyUsername $processedContent.ProxyUsername -ProxyPassword $processedContent.ProxyPassword

            # Print the HTTP status code
            if ($response -is [System.Net.HttpWebResponse]) {
                Write-Host "HTTP Status Code: $($response.StatusCode)" -ForegroundColor Cyan
            }

            # Process the response using Invoke-ProcessResponse
            if ($response) {
                Write-Verbose "Response:"
                Write-Verbose $response                
                Invoke-ProcessResponse -ResponseContent $response -RequestTemplate $processedContent.RequestContent
            }            
        }
    }
}
catch {
    Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
}
finally {
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}
