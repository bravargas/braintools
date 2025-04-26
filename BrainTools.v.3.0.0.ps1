[CmdletBinding()]
param (
    [string]$Environment = "MOCK", # Default to "QA"
    [string[]]$RequestFiles = $null # Optional parameter for specifying one or more request files
)

function Import-RequiredModules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$ModulePaths
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        foreach ($modulePath in $ModulePaths) {

            $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($modulePath)
            if (-not (Get-Module -Name $moduleName -ListAvailable)) {
                Import-Module -Force $modulePath -ErrorAction Stop
                Write-Host "$($MyInvocation.MyCommand.Name):: Imported module: $modulePath"
            }
            else {
                Write-Host "$($MyInvocation.MyCommand.Name):: Module already loaded: $moduleName"
            }
        }
      
    }
    catch {
        Write-Error "$($MyInvocation.MyCommand.Name):: Failed to import module: $modulePath. Error: $_"
        throw
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }      
}


Clear-Host

Write-Verbose "$($MyInvocation.MyCommand.Name):: START"


try {
    Set-Location -Path $PSScriptRoot

    Import-RequiredModules -ModulePaths @(
        ".\modules\ServicesTesting\ServicesTesting.1.0.0.psm1"
    )

    # Import the menu configuration
    . (Get-ConfigPath -ConfigName "Menu" -Environment $Environment)
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Imported menu configuration for environment: $Environment"    


    $testFile = "$PSScriptRoot\hello_world.txt"
    Test-FileExists -FilePath $testFile
    Write-Host "File exists: $testFile"    

}
catch {
    Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
}
finally {
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}