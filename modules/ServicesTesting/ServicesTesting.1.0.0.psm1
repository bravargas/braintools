# Helper function to check if a file exists
function Test-FileExists {
    param (
        [string]$FilePath
    )

    if (-not (Test-Path -Path $FilePath)) {
        throw "File not found: $FilePath"
    }
}

# Centralized configuration paths
function Get-ConfigPath {
    param (
        [string]$ConfigName,
        [string]$Environment
    )

    switch ($ConfigName) {
        "Hosts" { return "$PSScriptRoot\Config\parameters.$($Environment.ToLower()).xml" }
        "Menu" { return "$PSScriptRoot\Config\MenuConfig.$($Environment.ToLower()).ps1" }
        default { throw "Unknown configuration name: $ConfigName" }
    }
}