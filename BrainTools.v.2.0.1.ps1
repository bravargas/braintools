[CmdletBinding()]
param (
    [string]$Environment = "MOCK", # Default to "QA"
    [string]$ProfileName = "All", # Default to "QA"
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
            $processedContent = Invoke-RequestFile -FilePath $RequestFile -Verbose:$VerbosePreference

            # Invoke the request
            $response = Invoke-Request -RequestContent $processedContent.RequestContent -Certificate $processedContent.Certificate -ProxyUrl $processedContent.ProxyUrl -ProxyUsername $processedContent.ProxyUsername -ProxyPassword $processedContent.ProxyPassword -Verbose:$VerbosePreference

            # Process the response
            if ($response) {
                Invoke-ProcessResponse -ResponseContent $response -RequestTemplate $processedContent.RequestContent -Verbose:$VerbosePreference
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
        [string[]]$ModuleKeys
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {
        foreach ($key in $ModuleKeys) {
            if ($Global:ModuleMap.ContainsKey($key)) {
                $modulePath = $Global:ModuleMap[$key]
                $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($modulePath)

                if (-not (Get-Module -Name $moduleName)) {
                    Import-Module -Force $modulePath -ErrorAction Stop
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Imported module: $moduleName"
                } else {
                    Write-Verbose "$($MyInvocation.MyCommand.Name):: Module already loaded: $moduleName"
                }
            } else {
                Write-Warning "Unknown module key: $key"
            }
        }
    }
    catch {
        Write-Error "$($MyInvocation.MyCommand.Name):: Failed to import module. Error: $_"
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
            $menuOptions = @("SOAP and REST Services Testing", "---", "Database Queries", "---", "Test Endpoints","---", "IIS Report")
            Show-Menu -Options $menuOptions -Verbose:$VerbosePreference

            $choice = Get-UserChoice -MaxOption $menuOptions.Length
            switch ($choice) {
                "1" {
                    Import-RequiredModules -ModuleKeys @("ServicesTesting")
                    Set-ServicesEnvironment -Environment $Environment -Verbose:$VerbosePreference
                    Invoke-ServicesMenu -ProfileName $ProfileName -Verbose:$VerbosePreference
                }
                "2" {
                    Import-RequiredModules -ModuleKeys @("DBQueries")
                    Set-DBQueriesEnvironment -Environment $Environment -Verbose:$VerbosePreference
                    Invoke-DatabaseQueriesMenu -Verbose:$VerbosePreference
                }
                "3" {
                    Import-RequiredModules -ModuleKeys @("EndpointsTest")
                    Test-Endpoints -Verbose:$VerbosePreference
                }
                "4" {
                    Import-RequiredModules -ModuleKeys @("IISReport")
                    Invoke-IISReport -AsHtml -Show -Verbose:$VerbosePreference
                }
                "0" { return }
                default { Write-Host "Invalid option. Please try again." -ForegroundColor Red }
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


try {
    Clear-Host
    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    Set-Location -Path $PSScriptRoot

    # Example usage of the Environment parameter
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Using environment: $Environment"

    $Global:ModuleMap = @{
        "ServicesTesting" = ".\modules\ServicesTesting\ServicesTesting.1.0.0.psm1"
        "UtilsModule"     = ".\modules\General\UtilsModule.2.7.psm1"
        "DBQueries"       = ".\modules\DBQueries\DBQueries.1.0.0.psm1"
        "EndpointsTest"   = ".\modules\EndPoints\EndpointsTest.0.0.1.psm1"
        "IISReport"       = ".\modules\IISTool\IISReport.0.0.1.psm1"
    }

    Import-RequiredModules -ModuleKeys @("UtilsModule")
    
    Invoke-UserMenu

}
catch {
    Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
}
finally {
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}
