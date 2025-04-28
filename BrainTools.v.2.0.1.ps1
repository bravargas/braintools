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
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    } 
    finally {
        exit
    }
}


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
            Write-Verbose "$($MyInvocation.MyCommand.Name):: Trying to load module $moduleName from $modulePath"

            if (-not (Get-Module -Name $moduleName -ListAvailable)) {
                Import-Module -Force $modulePath -ErrorAction Stop
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Imported module: $modulePath"
            }
            else {
                Write-Verbose "$($MyInvocation.MyCommand.Name):: Module already loaded: $moduleName"
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

function Invoke-UserMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        while ($true) {
            #Clear-Host
            $menuOptions = @("SOAP and REST Services Testing","---", "Database Queries","---", "Test Endpoints", "---")
            Show-Menu -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length
            switch ($choice) {
                "1" { Invoke-ServicesMenu }
                "2" { Invoke-DatabaseQueriesMenu }
                "3" { Test-Endpoints }
                #"3" { Test-Endpoints -ConfigFilePath ".\modules\EndPoints\web.config"  }
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

    # Example usage of the Environment parameter
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Using environment: $Environment"

    Import-RequiredModules -ModulePaths @(
        ".\modules\ServicesTesting\ServicesTesting.1.0.0.psm1",
        ".\modules\General\UtilsModule.2.7.psm1",
        ".\modules\DBQueries\DBQueries.1.0.0.psm1",
        ".\modules\EndPoints\EndpointsTest.0.0.1.psm1"
    )

    # Set the environment for the modules
    Set-ServicesEnvironment -Environment $Environment

    Set-DBQueriesEnvironment -Environment $Environment

    Invoke-UserMenu

}
catch {
    Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
}
finally {
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}
