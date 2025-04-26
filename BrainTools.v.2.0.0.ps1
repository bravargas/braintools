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
    } 
    catch {
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    } 
    finally {
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
        "Hosts" { return "$PSScriptRoot\Config\parameters.$($Environment.ToLower()).xml" }
        "Menu" { return "$PSScriptRoot\Config\MenuConfig.$($Environment.ToLower()).ps1" }
        "ServicesMenu" { return "$PSScriptRoot\Config\ServicesMenu.$($Environment.ToLower()).ps1" }
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

function Invoke-StandardMenu {
    [CmdletBinding()]
    param (
        [string]$Title,
        [object[]]$Options
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        # Display the menu with default options from the configuration file
        Show-Menu -Title $Title -Options $Options -Header $menuConfig.Header -DividerLine $menuConfig.DividerLine -ExitOption $menuConfig.ExitOption
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
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Searching for certificate with $SearchBy : $SearchValue" 
        # Validate PfxCertificateAndPwd format
        if ($SearchBy -eq 'PfxCertificateAndPwd' -and $SearchValue -notmatch '.+\|.+') {
            throw "Invalid format for PfxCertificateAndPwd. Expected 'filename|password'."
        }

        if ($SearchBy -eq 'PfxCertificateAndPwd') {
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Searching for certificate in file: $SearchValue"   
            # Split the combined credential into filename and password
            $fileName, $Password = $SearchValue -split '\|' 

            Write-Verbose "$($MyInvocation.MyCommand.Name):: File name: $fileName, Password: $Password"   
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
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Store not provided. Using LocalMachine\My as default."
                $Store = 'LocalMachine\My'
            }

            # Call Find-Certificate with the appropriate search criteria
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Searching for certificate in store: $Store with $SearchBy : $SearchValue"
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

        # Load the hosts configuration (now XML)
        $hostsFilePath = Get-ConfigPath -ConfigName "Hosts"
        Test-FileExists -FilePath $hostsFilePath
        [xml]$hostsConfig = Get-Content -Path $hostsFilePath -Raw
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Loaded hosts file: $hostsFilePath"

        # Extract placeholders
        $placeholders = ([regex]::Matches($requestContent, '{{(.*?)}}') | ForEach-Object { $_.Groups[1].Value }).Trim()
        $resolvedPlaceholders = @{}
        $inputRequiredPlaceholders = @{}

        # Include global request parameters
        if ($hostsConfig.Parameters.GlobalRequestParameters) {
            foreach ($node in $hostsConfig.Parameters.GlobalRequestParameters.ChildNodes) {
                if ($node.Attributes["isExpression"] -and $node.Attributes["isExpression"].Value -eq "true") {
                    # Evaluate the expression in the node value
                    $evaluatedValue = Invoke-Expression $node.InnerText
                    $resolvedPlaceholders[$node.Name] = $evaluatedValue
                }
                else {
                    $resolvedPlaceholders[$node.Name] = $node.InnerText
                }
            }
        }

        # Load LocalRequestParameters from parameters.<environment>.xml
        $localParams = @{}
        if ($hostsConfig.Parameters.LocalRequestParameters) {
            foreach ($node in $hostsConfig.Parameters.LocalRequestParameters.ChildNodes) {
                $localParams[$node.Name] = $node.InnerText
            }
        }

        # Initialize optional parameters for Invoke-Request
        $certificate = $null
        $proxyUrl = $null
        $proxyUsername = $null
        $proxyPassword = $null

        foreach ($placeholder in $placeholders) {
            $placeholderName = $placeholder.Trim('{}')

            if ($placeholderName.StartsWith('#')) {
                # Handle host placeholders with #
                $hostKey = $placeholderName.TrimStart('#')
                $hostNode = $hostsConfig.Parameters.Hosts.Host | Where-Object { $_.name -eq $hostKey }
                if (-not $hostNode) {
                    throw "Host placeholder '$placeholderName' not found in hosts file."
                }
                $resolvedPlaceholders[$placeholderName] = $hostNode.host

                # Handle certificate if required
                if ($hostNode.UseCertificate -and $hostNode.UseCertificate.enabled -eq "true") {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Certificate required for host '$hostKey'. Fetching certificate..."
                    $certificate = Get-Certificate -SearchBy $hostNode.UseCertificate.SearchBy -SearchValue $hostNode.UseCertificate.SearchValue -Store $hostNode.UseCertificate.Store
                    if (-not $certificate) {
                        throw "Failed to retrieve the required certificate for host '$hostKey'."
                    }
                }

                # Handle proxy if required
                if ($hostNode.UseProxy -and $hostNode.UseProxy.enabled -eq "true") {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Proxy required for host '$hostKey'. Configuring proxy..."
                    $proxyUrl = $hostNode.UseProxy.proxyUrl
                    $proxyUsername = $hostNode.UseProxy.proxyUsername
                    $proxyPassword = $hostNode.UseProxy.proxyPassword
                }
            }
            else {
                # Check if the placeholder exists in GlobalRequestParameters
                if ($resolvedPlaceholders.ContainsKey($placeholderName)) {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Using global parameter for $placeholderName."
                }
                else {
                    # Retrieve the default parameter value from LocalRequestParameters
                    $defaultValue = if ($Global:Parameters.ContainsKey($placeholderName)) { $Global:Parameters[$placeholderName] } elseif ($localParams.ContainsKey($placeholderName)) { $localParams[$placeholderName] } else { '' }

                    # Prompt the user for input if no default value is found
                    $userInput = Read-Host "Enter the value for $placeholderName (default: $defaultValue)"
                    $manualParameter = if ([string]::IsNullOrWhiteSpace($userInput)) { $defaultValue } else { $userInput }
                    $resolvedPlaceholders[$placeholderName] = $manualParameter
                    $inputRequiredPlaceholders[$placeholderName] = $manualParameter
                    $Global:Parameters[$placeholderName] = $resolvedPlaceholders[$placeholderName]

                    # Update or insert the parameter in the parameters.<environment>.xml file
                    $null = Update-OrInsertParameter -ParamName $placeholderName -ParamValue $inputRequiredPlaceholders[$placeholderName]
                }
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
        $response = Invoke-WebRequest @params -UseBasicParsing

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
                        Write-Verbose "Node '$node' not found."
                        $currentNode = $null
                        break
                    }
                }
            }
            if ($expression) {
                $value = Invoke-Expression $expression
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
                    Write-Verbose "Node '$node' not found."
                    $currentNode = $null
                    break
                }
            }
        }

        if ($currentNode -and -not [string]::IsNullOrWhiteSpace($currentNode.InnerText)) {

            if ($null -ne $globalVariableName -and $globalVariableName -ne "") {        
                $value = $currentNode.InnerText

                if ($expression) {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Evaluating expression: $expression"
                    # Evaluate the expression in the context of the current node
                    $value = Invoke-Expression $expression
                }

                $Global:Parameters[$globalVariableName] = $value
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Stored value in global variable '$globalVariableName'."
            }
            else {
                $value = $currentNode
            }
            if ($display -eq "true") {
                Write-Host "Extracted Value ($path): " -ForegroundColor Green
                # Format and print the XML content with proper indentation
                #Write-Host (PrettyPrint-Xml -XmlString $currentNode.InnerXml -Indent 4)  -ForegroundColor White
                $value
                Write-Host " "
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
        [string]$ParamName,
        [string]$ParamValue
    )

    try {
        # Get the parameters.<environment>.xml file path
        $paramsFilePath = Get-ConfigPath -ConfigName "Hosts"
        # Check if the file exists
        if (-not (Test-Path -Path $paramsFilePath)) {
            throw "File not found: $paramsFilePath"
        }
        # Load the XML content
        [xml]$xmlContent = Get-Content -Path $paramsFilePath -Raw
        # Ensure the <LocalRequestParameters> section exists
        $parametersSection = $xmlContent.Parameters.LocalRequestParameters
        if (-not $parametersSection) {
            $parametersSection = $xmlContent.CreateElement("LocalRequestParameters")
            $xmlContent.Parameters.AppendChild($parametersSection) | Out-Null
        }
        # Check if the parameter already exists
        $existingParamNode = $parametersSection.SelectSingleNode($ParamName)
        if ($existingParamNode) {
            $existingParamNode.InnerText = $ParamValue
        } 
        else {
            # Insert the parameter as <parametername>value</parametername>
            $newParamNode = $xmlContent.CreateElement($ParamName)
            $newParamNode.InnerText = $ParamValue
            $parametersSection.AppendChild($newParamNode) | Out-Null
        }
        # Save the updated XML back to the file
        $xmlContent.Save($paramsFilePath)
        Write-Verbose "Parameter '$ParamName' updated or inserted successfully in $paramsFilePath"
        return $ParamValue
    }
    catch {
        Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
    }
}

function Invoke-ServicesMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        # Import the menu configuration
        . (Get-ConfigPath -ConfigName "ServicesMenu")

        # Extract the 'Name' property from each option
        $menuOptions = $servicesMenu.Options | ForEach-Object { $_.Name }

        # Keep showing the menu until the user selects the exit option
        while ($true) {
            Invoke-StandardMenu -Title $menuConfig.Title -Options $menuOptions
            $servicesMenu.Options = $servicesMenu.Options | Where-Object { $_.Name -ne $menuConfig.DividerLine }
            $userChoice = Get-UserChoice -MaxOption $servicesMenu.Options.Length

            if ($userChoice -eq 0) {
                Write-Host $menuConfig.ExitMessage -ForegroundColor Green
                break
            }
            else {
                $selectedOption = $servicesMenu.Options[$userChoice - 1]
                Write-Host "You selected: $($selectedOption.Name)" -ForegroundColor Cyan
                Write-Host "File Path: $($selectedOption.FilePath)" -ForegroundColor Yellow

                # Process the selected request file
                $processedContent = Invoke-RequestFile -FilePath $selectedOption.FilePath
                Write-Host "Processing. If you want to see the request content use -Verbose mode..." -ForegroundColor Green

                # Format and print the XML content with proper indentation
                Write-Verbose (PrettyPrint-Xml -XmlString $processedContent.RequestContent.OuterXml -RootElement "Root" -Indent 4)
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
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}


# SQL Section START
function Invoke-DatabaseQueriesMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        while ($true) {
            #Clear-Host
            $menuOptions = @("Scripts Menu", "List Tables", "Switch or refresh catalog")
            Invoke-StandardMenu -Title $menuConfig.Title -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length
            switch ($choice) {
                "1" { Invoke-ScriptsMenu }
                "2" { Invoke-TablesMenu }
                "3" { Select-Catalog -ConnectionStrings $connectionStrings }
                "0" { return }
                default { Write-Host "Invalid option. Please try again." -ForegroundColor Red }
            }
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

function Invoke-ScriptsMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "SQL\scripts"
        #$scriptPath = Join-Path -Path $scriptPath -ChildPath "$global:SelectedSystem"

        $scripts = Get-ChildItem -Path $scriptPath -Filter "*.sql"
        while ($true) {
            #Clear-Host

            $counter = 1
            $menuOptions = @() # Initialise the array

            foreach ($script in $scripts) {
                $shortScriptName = $script.Name.Replace(".sql", "")
                $menuOptions += $shortScriptName # Add to the array
                $counter++
            }

            $menuTitle = "Scripts Menu"
            Invoke-StandardMenu -Title $menuTitle -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length

            if ($choice -eq "0") {
                return
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -le $scripts.Count) {
                $selectedScript = $scripts[[int]$choice - 1]
                #Invoke-SqlScript -ScriptPath $selectedScript.FullName -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
                Invoke-SqlScript -ScriptPath $selectedScript.FullName 
            }
            else {
                Write-Host "Invalid option. Please try again." -ForegroundColor Red
            }
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

function Invoke-SqlScript {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $false)]
        [bool]$SkipShowDataTable = $false,
        [Parameter(Mandatory = $false)]
        [bool]$SkipSaveDataTable = $false
    )

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        # Load the SQL file content
        $scriptContent = Get-Content -Path $ScriptPath -Raw

        # Find all tags in the SQL file contents
        $tags = ([regex]::matches($scriptContent, "(\{{.*?\}})").captures | ForEach-Object { $_.Value })

        # Get user input for each tag
        $tagValues = Get-TagValues -tags $tags

        # Replace tags with user input values
        foreach ($tag in $tags) {
            $scriptContent = $scriptContent -replace [regex]::Escape($tag), $tagValues[$tag]
        }

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
        Invoke-Query -Query $scriptContent -BaseName $baseName -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Invoke-Query {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [Parameter(Mandatory = $true)]
        [string]$BaseName,
        [Parameter(Mandatory = $false)]
        [bool]$SkipShowDataTable = $false,
        [Parameter(Mandatory = $false)]
        [bool]$SkipSaveDataTable = $false
    )

    if ($SkipShowDataTable -and $SkipSaveDataTable) {
        throw "You cannot skip both Show-DataTable and Save-DataTable."
    }

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        $results = Get-SqlData -query $Query

        if ($results) {
            if (-not $SkipShowDataTable) {
                Show-DataTable -DataTable $results -DisplayMode "GridView" -Title $BaseName
            }
            if (-not $SkipSaveDataTable) {
                Save-DataTable -BaseName $BaseName -QueryResults $results
            }
        }
        else {
            Write-Host "No results returned"
            Read-Host -Prompt "Press any key to continue..."
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

function Save-DataTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseName,
        [Parameter(Mandatory = $true)]
        [System.Array]$QueryResults
    )

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

        $outputPath = Join-Path -Path $PSScriptRoot -ChildPath "results"
        $outputPath = Join-Path -Path $outputPath -ChildPath "$global:SelectedSystem"

        $outputFile = Join-Path -Path $outputPath -ChildPath "$($BaseName)_$($timestamp).csv"

        Export-ToCSV -dataTable $QueryResults -outputFilePath $outputFile
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

# SQL Section END


function Invoke-UserMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        while ($true) {
            #Clear-Host
            $menuOptions = @("SOAP and REST Services Testing", "Database Queries")
            Invoke-StandardMenu -Title $menuConfig.Title -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length
            switch ($choice) {
                "1" { Invoke-ServicesMenu }
                "2" { Invoke-DatabaseQueriesMenu }
                "3" { Select-Catalog -ConnectionStrings $connectionStrings }
                "0" { return }
                default { Write-Host "Invalid option. Please try again." -ForegroundColor Red }
            }
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

try {
    Clear-Host
    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    Set-Location -Path $PSScriptRoot


    $global:ScriptVersion = "v2.0.0"
    $global:ModuleVersion = "2.7"

    $moduleName = "UtilsModule.$global:ModuleVersion"
    $modulePath = "..\library\$moduleName.psm1"

    # Remove the module if it is already loaded
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName
        Write-Verbose "Module '$moduleName' has been removed."
    }
    else {
        Write-Verbose "Module '$moduleName' is not loaded."
    }

    # Import the latest version of the module
    Import-Module $modulePath
    Write-Verbose "Module '$moduleName' has been imported from '$modulePath'."

    # Import the menu configuration. This one is global and will be used in all menus
    . (Get-ConfigPath -ConfigName "Menu")

    # Example usage of the Environment parameter
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Using environment: $Environment"

    Invoke-UserMenu


}
catch {
    Write-ErrorLog -FunctionName $MyInvocation.MyCommand.Name -ErrorMessage $_
}
finally {
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}
