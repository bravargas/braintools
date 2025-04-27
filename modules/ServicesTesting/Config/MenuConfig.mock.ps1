# BrainTools ASCII Banner
$asciiArt = @'
    ____             _     ______            __    
   / __ )_________ _(_)___/_  __/___  ____  / /____
  / __  / ___/ __ `/ / __ \/ / / __ \/ __ \/ / ___/
 / /_/ / /  / /_/ / / / / / / / /_/ / /_/ / (__  ) 
/_____/_/   \__,_/_/_/ /_/_/  \____/\____/_/____/  
                               By Brainer Vargas
'@

# Display the ASCII banner
$DividerLine = "---" # Divider line
#Write-Host $asciiArt -ForegroundColor Cyan

# Menu Configuration
$MenuConfig = @{
    Title  = "Welcome. Please select an option:"
    Header = $asciiArt -split "`r?`n"
    DividerLine = $DividerLine
    ExitOption = "Exit"
    ExitMessage = "Exiting the menu. Adios!"
}
