function Get-ProcessUsingPort {
    param (
        [int]$Port
    )

    if ($IsWindows) {
        $netstatOutput = netstat -ano | Select-String ":$Port\s+.*LISTENING\s+(\d+)"
        if ($netstatOutput) {
            $pid = ($netstatOutput -replace '.*LISTENING\s+', '') -as [int]
            return Get-Process -Id $pid -ErrorAction SilentlyContinue
        }
    }
    else {
        $lsofOutput = lsof -iTCP:$Port -sTCP:LISTEN -t 2>$null
        if ($lsofOutput) {
            return Get-Process -Id $lsofOutput -ErrorAction SilentlyContinue
        }
    }
    return $null
}


# Clear the console
Clear-Host

Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

Set-Location -Path $PSScriptRoot

# Configuration and mock response directory
$configFile = ".\mock.config.json"
$mockResponseDir = ".\mock_responses"

# Display all steps while starting the service
Write-Host "Starting the mock server..." -ForegroundColor Cyan
Write-Host "Loading configuration file: $configFile" -ForegroundColor Yellow
Write-Host "Mock responses directory: $mockResponseDir" -ForegroundColor Yellow

# Check if configuration file exists
if (-not (Test-Path $configFile)) {
    Write-Host "Configuration file not found: $configFile" -ForegroundColor Red
    exit
}

# Load configuration
$config = Get-Content -Path $configFile -Raw | ConvertFrom-Json

# Dynamically generate mock configuration from MenuConfig.ps1
Write-Host "Generating mock configuration dynamically from MenuConfig.ps1..." -ForegroundColor Cyan

# Import the menu configuration
$menuPath = Join-Path $PSScriptRoot ".." "modules" "ServicesTesting" "Config" "ServicesMenu.mock.ps1"
#. (Resolve-Path -Path $menuPath)

$servicesMenu = & (Resolve-Path -Path $menuPath) -ProfileName "All"
$mockConfig = @()

foreach ($option in $ServicesMenu.Options) {
    if($option.FilePath -eq "") {
        continue
    }
    $filePath = $option.FilePath
    $requestContent = Get-Content -Path "..\modules\ServicesTesting\$filePath" -Raw
    [xml]$xmlContent = $requestContent

    $type = $xmlContent.requestTemplate.type
    $path = $xmlContent.requestTemplate.path
    $method = $xmlContent.requestTemplate.method
    $responseFileName = $filePath.Replace("request", "response").Replace("\Requests", "\Responses")

    # Extract bodyContains logic for SOAP requests
    $bodyContains = $null
    if ($type -eq "SOAP") {
        $bodyNode = $xmlContent.requestTemplate.body.SelectSingleNode("//*[local-name()='Body']")
        if ($bodyNode -and $bodyNode.HasChildNodes) {
            $bodyContains = $bodyNode.FirstChild.LocalName
        }
    }

    $mockConfig += [pscustomobject]@{
        path           = $path
        method         = $method
        responseFile   = $responseFileName
        contentType    = $xmlContent.requestTemplate.headers.header | Where-Object { $_.name -eq "Content-Type" } | Select-Object -ExpandProperty value
        matchCondition = if ($bodyContains) { @{ bodyContains = $bodyContains } } else { $null }
    }
}

Write-Host "Mock configuration generated dynamically:" -ForegroundColor Green
$mockConfig | Format-Table -AutoSize

# Check if the port is already in use
$port = 8088

# Kill any existing mock server process using the same port
$existingProcess = Get-ProcessUsingPort -Port $port
if ($existingProcess) {
    Write-Host "Port $port is already in use by process $($existingProcess.Id) ($($existingProcess.ProcessName)). Attempting to stop it..." -ForegroundColor Yellow
    try {
        Stop-Process -Id $existingProcess.Id -Force -ErrorAction Stop
        Write-Host "Process stopped." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to stop the process using port $port. Please stop it manually." -ForegroundColor Red
        exit
    }
}

# Double check port is now free
$checkAgain = Get-ProcessUsingPort -Port $port
if ($checkAgain) {
    Write-Host "Port $port is still in use. Please stop the process using it and try again." -ForegroundColor Red
    exit
}

# Create an HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$script:listener = $listener

# Ctrl+C handler
$null = Register-EngineEvent -SourceIdentifier Console_Cancel_Key_Press -Action {
    Write-Host "`nCtrl+C detected. Stopping the mock server..." -ForegroundColor Cyan
    if ($script:listener -and $script:listener.IsListening) {
        $script:listener.Stop()
    }
    Unregister-Event -SourceIdentifier Console_Cancel_Key_Press
    exit
}

Write-Host "Type 'STOP' to stop the mock server." -ForegroundColor Yellow

try {
    $listener.Start()
    Write-Host "Mock server running at http://localhost:$port/"

    while ($listener.IsListening) {
        if ([Console]::KeyAvailable) {
            $keyInput = [Console]::ReadLine()
            if ($keyInput -eq "STOP") {
                Write-Host "Stopping the mock server..." -ForegroundColor Cyan
                break
            }
        }

        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # Display the incoming request in the console
        Write-Host "Incoming Request:" -ForegroundColor Cyan
        Write-Host ("Method: {0}" -f $request.HttpMethod) -ForegroundColor Yellow
        Write-Host ("URL: {0}" -f $request.Url.AbsoluteUri) -ForegroundColor Yellow

        # Corrected header display logic
        Write-Host "Headers:" -ForegroundColor Yellow
        $request.Headers.AllKeys | ForEach-Object {
            Write-Host ("  {0}: {1}" -f $_, $request.Headers[$_]) -ForegroundColor White
        }

        # Display body if available
        if ($request.HasEntityBody) {
            $bodyReader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $requestBody = $bodyReader.ReadToEnd()
            $bodyReader.Close()
            Write-Host "Body:" -ForegroundColor Yellow
            Write-Host $requestBody -ForegroundColor White
        }

        # Find the matching route based on the path, method, and matchCondition
        $route = $config.routes | Where-Object {
            $_.path -eq $request.Url.AbsolutePath -and
            $_.method -eq $request.HttpMethod -and
            ($_.matchCondition.bodyContains -eq $null -or $requestBody -match $_.matchCondition.bodyContains)
        }

        if ($null -ne $route) {
            $responseFilePath = Join-Path -Path $mockResponseDir -ChildPath $route.responseFile
            if (Test-Path $responseFilePath) {
                $responseBody = Get-Content -Path $responseFilePath -Raw
                $response.ContentType = $route.contentType
                $response.StatusCode = 200
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
                $response.OutputStream.Write($buffer, 0, $buffer.Length)

                # Display the response and file used
                if ($route.matchCondition.bodyContains) {
                    Write-Host "Response Body Contains: $($route.matchCondition.bodyContains)" -ForegroundColor Yellow
                }
                Write-Host "Response Status Code: $($response.StatusCode)" -ForegroundColor Green
                Write-Host "Response File: $responseFilePath" -ForegroundColor Green
                Write-Host "Response Content:" -ForegroundColor Green
                Write-Host $responseBody -ForegroundColor White
            }
            else {
                $response.StatusCode = 404
                $responseBody = "Mock response file not found: $responseFilePath"
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
        }
        else {
            $response.StatusCode = 404
            $responseBody = "No matching route found for path: $($request.Url.AbsolutePath) and method: $($request.HttpMethod)"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)

            Write-Host "No matching route found for the request." -ForegroundColor Red
        }

        $response.Close()
    }
}
catch {
    Write-Host "An error occurred: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($listener -and $listener.IsListening) {
        $listener.Stop()
        Write-Host "Mock server stopped." -ForegroundColor Green
    }
    Unregister-Event -SourceIdentifier Console_Cancel_Key_Press
}
