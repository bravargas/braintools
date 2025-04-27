function Get-DBQueriesConfigPath {
    param (
        [string]$ConfigName
    )

    Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

    try {    

        switch ($ConfigName) {
            "SQLServerConnection" { return "$PSScriptRoot\Config\SQLServerConnection.$($Environment.ToLower()).xml" }
            default { throw "Unknown configuration name: $ConfigName" }
        }
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }    
}

function Invoke-DatabaseQueriesMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        # Load the hosts configuration (now XML)
        $SQLServerConnectionFilePath = Get-DBQueriesConfigPath -ConfigName "SQLServerConnection"
        Test-FileExists -FilePath $SQLServerConnectionFilePath
        [xml]$SQLServerConnection = Get-Content -Path $SQLServerConnectionFilePath -Raw
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Loaded SQLServerConnection file: $SQLServerConnectionFilePath"
        $XPath = $SQLServerConnection.Configurations.Configuration.XPath
        $ConfigFilePath = $SQLServerConnection.Configurations.ConfigFilePath

        # Check if the request file exists
        Test-FileExists -FilePath $ConfigFilePath        

        $connectionString = Get-ConfigValues -XPath $XPath -ConfigFilePath $ConfigFilePath
        # Open the SQL connection
        $global:connection = Open-SQLConnection -connectionString $connectionString

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

        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "scripts"
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

function Invoke-TablesMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

        $tables = Get-SqlData -query "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS FullName FROM INFORMATION_SCHEMA.TABLES ORDER BY FullName"

        while ($true) {
            #Clear-Host
            
            $counter = 1
            $menuOptions = @() # Initialise the array
            foreach ($table in $tables) {
                $tableFullName = $table.FullName
                $menuOptions += $tableFullName # Add to the array
                $counter++
            }

            $menuTitle = "DB Tables List Menu"
            Show-Menu -Title $menuTitle -Options $menuOptions


            $choice = Get-UserChoice -MaxOption $menuOptions.Length

            if ($choice -eq "0") {
                return
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -le $tables.Count) {
                $selectedTable = $tables[[int]$choice - 1].FullName
                #Invoke-TableQuery -TableName $selectedTable -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
                Invoke-TableQuery -TableName $selectedTable -SkipShowDataTable $false -SkipSaveDataTable $false
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

function Invoke-TableQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $false)]
        [bool]$SkipShowDataTable = $false,
        [Parameter(Mandatory = $false)]
        [bool]$SkipSaveDataTable = $false
    )

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        if ([string]::IsNullOrWhiteSpace($TableName)) {
            throw "TableName cannot be null or empty."
        }

        $query = "SELECT TOP 500 * FROM $TableName;"
        Write-Verbose "Executing query: $query"
        Invoke-Query -Query $query -BaseName $TableName -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
    }
    catch {
        Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
        Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}