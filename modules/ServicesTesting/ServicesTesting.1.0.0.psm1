$script:Environment = $null

function Set-ServicesEnvironment {
    param ($Environment)
    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try { 
        $script:Environment = $Environment
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

# Centralized configuration paths
function Get-ServicesConfigPath {
    param (
        [string]$ConfigName 
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {    

        Write-Verbose "$($MyInvocation.MyCommand.Name):: Looking for configuration file for $ConfigName"
        switch ($ConfigName) {
            "Hosts" { 
                return "$PSScriptRoot\Config\parameters.$($script:Environment.ToLower()).xml" 
            }
            "Menu" { 
                return "$PSScriptRoot\Config\MenuConfig.$($script:Environment.ToLower()).ps1" 
            }
            "ServicesMenu" { 
                return "$PSScriptRoot\Config\ServicesMenu.$($script:Environment.ToLower()).ps1" 
            }
            default { 
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Unknown configuration name: $ConfigName" -ForegroundColor Red
                throw "Unknown configuration name: $ConfigName" 
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

# Helper function to resolve placeholders
function Resolve-Placeholders {
    param (
        [string]$Content,
        [hashtable]$ResolvedPlaceholders
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {

        foreach ($key in $ResolvedPlaceholders.Keys) {
            $escapedKey = [regex]::Escape($key)
            $Content = $Content -replace "{{\s*$escapedKey\s*}}", $ResolvedPlaceholders[$key]
        }

        return $Content
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }	    
}

#Specific functions for the services module
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
        $hostsFilePath = Get-ServicesConfigPath -ConfigName "Hosts"
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
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
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

        # Prepare parameters for IWR
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
     
        # Make the HTTP request using IWR
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
        if ($_.ErrorDetails.Message) {
            Write-Host "Error Detail: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        }
        if ($_.Exception.InnerException) {
            Write-Host "Inner Exception: $($_.Exception.InnerException.Message)" -ForegroundColor Red
        }
        return $null
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
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
                Write-Host (Invoke-PrettyPrintXml -XmlString $ResponseContent -Indent 4) -ForegroundColor White
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
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
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

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        # Get the parameters.<environment>.xml file path
        $paramsFilePath = Get-ServicesConfigPath -ConfigName "Hosts"
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
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Parameter '$ParamName' updated or inserted successfully in $paramsFilePath"
        return $ParamValue
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }	    
}

function Invoke-ServicesMenu {
    [CmdletBinding()]
    param (
        [string]$ProfileName = "All"
    )

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        # Import the menu configuration
        $servicesMenu = Get-ServicesMenu -ProfileName $ProfileName


        # Extract the 'Name' property from each option
        $menuOptions = $servicesMenu.Options | ForEach-Object { $_.Name }

        # Keep showing the menu until the user selects the exit option
        while ($true) {
            Show-Menu -Options $menuOptions

            $servicesMenu.Options = $servicesMenu.Options | Where-Object {
                $_.Name -ne $servicesMenu.DividerLine -and
                -not $_.Name.StartsWith($servicesMenu.SubTitlePrefix)
            }
            
            $userChoice = Get-UserChoice -MaxOption $servicesMenu.Options.Length

            if ($userChoice -eq 0) {
                Write-Host "Exiting the menu. Adios!" -ForegroundColor Green
                break
            }
            else {
                $selectedOption = $servicesMenu.Options[$userChoice - 1]
                Write-Host "You selected: $($selectedOption.Name)" -ForegroundColor Cyan
                Write-Host "File Path: $($selectedOption.FilePath)" -ForegroundColor Yellow

                # Process the selected request file
                $requestPath = Join-Path -Path $PSScriptRoot -ChildPath $selectedOption.FilePath
                $processedContent = Invoke-RequestFile -FilePath $requestPath
                Write-Host "Processing. If you want to see the request content use -Verbose mode..." -ForegroundColor Green

                # Format and print the XML content with proper indentation
                Write-Verbose (Invoke-PrettyPrintXml -XmlString $processedContent.RequestContent.OuterXml -RootElement "Root" -Indent 4)
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
                    try {
                        Write-Verbose ($response | Out-String)
                    }
                    catch {
                        Write-Verbose ($response | ConvertTo-Json -Depth 10)
                    }
                                   
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

function Get-ServicesMenu {
    [CmdletBinding()]
    param (
        [string]$ProfileName = "All",
        [string]$DividerLine = "---",
        [string]$SubTitlePrefix = ">",
        [string]$ConfigPath
    )

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "Config\ServicesMenu.psd1"
    }

    $config = Import-PowerShellDataFile -Path $ConfigPath
    $CategoryNames = $config.CategoryNames
    $ProfileCategories = $config.ProfileCategories
    
    # Create 'All' as an unique category that includes all categories
    $ProfileCategories["All"] = ($ProfileCategories.Values | ForEach-Object { $_ }) | Select-Object -Unique

    $categoryItems = $config.CategoryItems

    $allMenuItems = foreach ($category in $categoryItems.Keys) {
        foreach ($filename in $categoryItems[$category]) {
            [pscustomobject]@{
                Name     = "$($filename -replace '\.request\.xml$', '')"
                FilePath = ".\Requests\$category\$filename"
                Category = $category
            }
        }
    }

    $DividerItem = [pscustomobject]@{
        Name     = $DividerLine
        FilePath = ""
    }

    $options = foreach ($category in $ProfileCategories[$ProfileName]) {
        $items = $allMenuItems | Where-Object { $_.Category -eq $category }
        if ($items) {
            $longName = $CategoryNames[$category]
            if (-not $longName) { $longName = $category }

            [pscustomobject]@{
                Name     = "$SubTitlePrefix$longName"
                FilePath = ""
            }

            $DividerItem
            $items
            $DividerItem
        }
    }

    if ($options.Count -gt 0 -and $options[-1].Name -eq $DividerLine) {
        $options = $options[0..($options.Count - 2)]
    }

    return @{
        Title          = "Welcome. Please select an option:"
        DividerLine    = $DividerLine
        SubTitlePrefix = $SubTitlePrefix
        Options        = $options
    }
}


#End of specific functions for the services module