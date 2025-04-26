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
$menuConfig = @{
    Title  = "Welcome. Please select an option:"
    Options = @(
        @{
            Name     = "TST - Dog Breeds"
            FilePath = ".\Requests\TST\DogBreeds.request.xml"
        },
        @{
            Name     = "TST - Dog Breeds Random Image"
            FilePath = ".\Requests\TST\DogBreedsRandomImage.request.xml"
        },      
        @{
            Name     = $DividerLine
        },          
        @{
            Name     = "TST - List Of Continents By Name"
            FilePath = ".\Requests\TST\ListOfContinentsByName.request.xml"
        },
        @{
            Name     = "TST - Capital City of a Country"
            FilePath = ".\Requests\TST\CapitalCity.request.xml"
        },        
        @{
            Name     = "TST - Ron Swanson Quotes"
            FilePath = ".\Requests\TST\ron-swanson-quotes.request.xml"
        },
        @{
            Name     = $DividerLine
        },           
        @{
            Name     = "ALH - Alert Hub Authenticate"
            FilePath = ".\Requests\ALH\AlertHubAuthenticate.request.xml"
        },
        @{
            Name     = "ALH - Alert Hub Delivery Basic Message"
            FilePath = ".\Requests\ALH\AlertHubDeliveryMessage.request.xml" 
        },
        @{
            Name     = "ALH - Alert Hub Notification Status"
            FilePath = ".\Requests\ALH\AlertHubNotificationStatus.request.xml" 
        }                 		
    )
    
    Header = $asciiArt -split "`r?`n"

    DividerLine = $DividerLine
    ExitOption = "Exit"
    ExitMessage = "Exiting the menu. Adios!"
}
