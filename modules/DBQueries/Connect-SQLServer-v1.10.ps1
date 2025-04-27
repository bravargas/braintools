[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = ".\SystemConfig-localhost.xml",
    [Parameter(Mandatory = $false)]
    [string]$System = "localhost",
    [Parameter(Mandatory = $false)]
    [string]$Table,
    [Parameter(Mandatory = $false)]
    [string]$Script,
    [Parameter(Mandatory = $false)]
    [bool]$SkipShowDataTable = $false,
    [Parameter(Mandatory = $false)]
    [bool]$SkipSaveDataTable = $false
)

if ($SkipShowDataTable -and $SkipSaveDataTable) {
    throw "You cannot skip both Show-DataTable and Save-DataTable."
}

function Invoke-UserMenu {
    [CmdletBinding()]
    param ()

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        while ($true) {
            #Clear-Host
            $menuTitle = "$scriptNameWithoutExtension - By Brainer Vargas"
            $menuOptions = @("Scripts Menu", "List Tables", "Switch or refresh catalog")
            Show-Menu -Title $menuTitle -Options $menuOptions

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
        $scriptPath = Join-Path -Path $scriptPath -ChildPath "$global:SelectedSystem"

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
            Show-Menu -Title $menuTitle -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length

            if ($choice -eq "0") {
                return
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -le $scripts.Count) {
                $selectedScript = $scripts[[int]$choice - 1]
                Invoke-SqlScript -ScriptPath $selectedScript.FullName -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
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

function Invoke-SystemOptionsMenu {
    [CmdletBinding()]
    param (
        [xml]$xml
    )

    try {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: START"
        while ($true) {
            #Clear-Host

            $menuOptions = @() # Initialise the array
            $xml.Configurations.Configuration | ForEach-Object {
                $menuOptions += $_.System # Add to the array
            }

            $menuTitle = "System Options Menu"
            Show-Menu -Title $menuTitle -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length

            if ($choice -eq "0") {
                return $null
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -le $menuOptions.Count) {
                $selectedSystem = $menuOptions[[int]$choice - 1]
                return $selectedSystem
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
                Invoke-TableQuery -TableName $selectedTable -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
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

function Select-Catalog {
    param (
        [string[]]$ConnectionStrings
    )

    $selectedConnectionString = Select-ConnectionString -ConnectionStrings $connectionStrings
    Write-Verbose "Selected connection string: $selectedConnectionString"

    try {
        if ($selectedConnectionString) {
            Write-Verbose "Opening SQL Server Connection..."

            # Open the SQL connection
            $global:connection = Open-SQLConnection -connectionString $selectedConnectionString

            if ($null -eq $global:connection) {
                Write-Verbose "Opening SQL Server Connection has failed"
                throw "An error occurred while attempting to open the SQL connection."
            }

            Write-Verbose "Opening SQL Server Connection has been completed..."
        }
        else {
            return
        }
    }
    catch {
        Write-Host "Error opening SQL connection: $_" -ForegroundColor Red
        Write-Verbose "Error details: $($_.Exception.Message)"
        throw
    }
    finally {
        Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Select-ConnectionString {
    param (
        [string[]]$ConnectionStrings
    )

    if ($ConnectionStrings.Count -eq 1) {
        return $ConnectionStrings[0]
    }
    else {
        $catalogs = @()
        foreach ($connectionString in $ConnectionStrings) {
            if ($connectionString -match "Initial Catalog=([^;]+)") {
                $catalogs += $matches[1]
            }
        }

        $selectedCatalog = $null
        while ($null -eq $selectedCatalog) {

            $menuOptions = @() # Initialise the array
            for ($i = 0; $i -lt $catalogs.Count; $i++) {
                $menuOptions += $catalogs[$i] # Add to the array
            }

            $menuTitle = "Available catalogs"
            Show-Menu -Title $menuTitle -Options $menuOptions

            $choice = Get-UserChoice -MaxOption $menuOptions.Length

            if ($choice -eq "0") {
                return
            }
            elseif ($choice -match '^\d+$' -and [int]$choice -le $catalogs.Count) {
                $selectedCatalog = $catalogs[[int]$choice - 1]
            }
            else {
                Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            }
        }

        return $ConnectionStrings[$catalogs.IndexOf($selectedCatalog)]
    }
}

function Get-ConfigFilePath {
    param (
        [string]$InitialConfigFilePath
    )

    Add-Type -AssemblyName System.Windows.Forms

    if (-not $InitialConfigFilePath -or -not (Test-Path -Path $InitialConfigFilePath)) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Cannot continue without a valid configuration file. Do you want to browse for the file?",
            "Configuration File Missing",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.InitialDirectory = $PSScriptRoot
            $openFileDialog.Filter = "XML files (*.xml)|*.xml|Configuration files (*.config)|*.config|All files (*.*)|*.*"
            $openFileDialog.Multiselect = $false

            $dialogResult = $openFileDialog.ShowDialog()

            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
                $ConfigFilePath = $openFileDialog.FileName
                Write-Host "Selected configuration file: $ConfigFilePath"
                return $ConfigFilePath
            }
            else {
                Write-Host "No file selected. Exiting script."
                exit
            }
        }
        else {
            Write-Host "User chose not to browse for a file. Exiting script."
            exit
        }
    }
    else {
        Write-Verbose "Configuration file found: $InitialConfigFilePath"
        return $InitialConfigFilePath
    }
}

Clear-Host

Write-Verbose "$($MyInvocation.MyCommand.Name):: START"

$global:ScriptVersion = "v1.10"
$global:ModuleVersion = "2.6"

try {
    Set-Location -Path $PSScriptRoot

    # --- Fast-path for Table/Script execution ---
    if ($PSBoundParameters.ContainsKey('Table') -or $PSBoundParameters.ContainsKey('Script')) {
        if (-not $System -or -not $ConfigFilePath) {
            Write-Host "Both -System and -ConfigFilePath must be provided when using -Table or -Script. Exiting." -ForegroundColor Red
            exit 1
        }
        $ConnectSQLServerConfig = "Connect-SQLServer.xml"
        if (-not (Test-Path -Path $ConnectSQLServerConfig)) {
            Write-Host "Cannot continue without a valid configuration file" -ForegroundColor Red
            exit 1
        }
        $moduleName = "UtilsModule.$global:ModuleVersion"
        $modulePath = "..\library\$moduleName.psm1"
        if (Get-Module -Name $moduleName) {
            Remove-Module -Name $moduleName
        }
        Import-Module $modulePath
        [xml]$config = Get-Content $ConnectSQLServerConfig
        $validSystems = $config.Configurations.Configuration.System
        if ($System -notin $validSystems) {
            Write-Host "Invalid system specified. Valid systems are: $($validSystems -join ', ')" -ForegroundColor Red
            exit 1
        }
        $matchingConfig = $config.Configurations.Configuration | Where-Object { $_.System -eq $System }
        if ($null -eq $matchingConfig) {
            Write-Host "Cannot continue without knowing what System to use" -ForegroundColor Red
            exit 1
        }
        $global:SelectedSystem = $System
        $XPath = $matchingConfig.XPath
        $connectionStrings = Get-ConfigValues -XPath $XPath -ConfigFilePath $ConfigFilePath
        $global:connection = $null
        Select-Catalog -ConnectionStrings $connectionStrings
        if ($null -eq $global:connection) {
            Write-Host "Cannot continue without a database connection" -ForegroundColor Red
            exit 1
        }
        if ($Table) {
            Invoke-TableQuery -TableName $Table -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
            exit 0
        } elseif ($Script) {
            $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "scripts"
            $scriptPath = Join-Path -Path $scriptPath -ChildPath "$global:SelectedSystem"
            $scriptFile = Join-Path -Path $scriptPath -ChildPath ("$Script.sql")
            if (-not (Test-Path $scriptFile)) {
                Write-Host "Script file '$scriptFile' not found." -ForegroundColor Red
                exit 1
            }
            Invoke-SqlScript -ScriptPath $scriptFile -SkipShowDataTable $SkipShowDataTable -SkipSaveDataTable $SkipSaveDataTable
            exit 0
        }
    }

    $ConfigFilePath = Get-ConfigFilePath -InitialConfigFilePath $ConfigFilePath

    $ConnectSQLServerConfig = "Connect-SQLServer.xml"
    if (-not (Test-Path -Path $ConnectSQLServerConfig)) {
        throw "Cannot continue without a valid configuration file"
    }

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

    # Load the XML configuration file
    [xml]$config = Get-Content $ConnectSQLServerConfig

    if ($null -eq $System -or $System.Length -eq 0) {
        $System = Invoke-SystemOptionsMenu -xml $config
    }

    # Validate the system parameter against the configuration file
    $validSystems = $config.Configurations.Configuration.System
    if ($System -notin $validSystems) {
        throw "Invalid system specified. Valid systems are: $($validSystems -join ', ')"
    }

    $scriptName = Split-Path -Path $MyInvocation.MyCommand.Path -Leaf
    $scriptNameWithoutExtension = $scriptName -replace '\.ps1$', ''

    # Find the matching configuration
    $matchingConfig = $config.Configurations.Configuration | Where-Object { $_.System -eq $System }

    if ($null -eq $matchingConfig) {
        throw "Cannot continue without knowing what System to use"
    }

    $global:SelectedSystem = $System

    # Assign the XPath from the matching configuration
    $XPath = $matchingConfig.XPath

    # Output the XPath for verification
    Write-Verbose "Using XPath: $XPath"

    $connectionStrings = Get-ConfigValues -XPath $XPath -ConfigFilePath $ConfigFilePath

    $global:connection = $null

    Select-Catalog -ConnectionStrings $connectionStrings

    if ($null -eq $global:connection) {
        throw "Cannot continue without a database connection"
    }

    if ($global:connection) {
        Invoke-UserMenu
        #Show-MainMenu
    }
}
catch {
    Write-Host "$($MyInvocation.MyCommand.Name):: An error occurred: $_" -ForegroundColor Red
    Write-Verbose "$($MyInvocation.MyCommand.Name):: Error details: $($_.Exception.Message)"
}
finally {
    Write-Verbose "$($MyInvocation.MyCommand.Name):: END"
}

#Invoke-SqlScript: Ejecuta un script SQL desde archivo, reemplazando etiquetas con valores proporcionados por el usuario.
#Invoke-Query: Ejecuta un query SQL y muestra los resultados en una vista tipo grid, luego los guarda.
#Save-DataTable: Guarda un DataTable en un archivo CSV con nombre según la fecha y hora.
#Show-TablesMenu: Muestra un menú para seleccionar tablas desde la BD.
#Get-ConnectionString: Carga cadenas de conexión desde un archivo XML.
#Open-SQLConnection: Abre una conexión SQL con la cadena especificada.
#Close-SQLConnection: Cierra la conexión SQL abierta.
#Get-SqlData: Ejecuta un query SQL y devuelve los resultados como DataTable.
#Export-ToCSV: Exporta un DataTable a un archivo CSV.
#Show-DataTable: Muestra un DataTable en formato tabla o vista tipo grid.
#Get-TagValues: Solicita valores al usuario según nombres de etiqueta encontrados en el script SQL.
