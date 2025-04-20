# BrainTools ASCII Banner
$asciiArt = @'
    ____             _     ______            __    
   / __ )_________ _(_)___/_  __/___  ____  / /____
  / __  / ___/ __ `/ / __ \/ / / __ \/ __ \/ / ___/
 / /_/ / /  / /_/ / / / / / / / /_/ / /_/ / (__  ) 
/_____/_/   \__,_/_/_/ /_/_/  \____/\____/_/____/  
'@

# Display the ASCII banner
#Write-Host $asciiArt -ForegroundColor Cyan

# Menu Configuration
$menuConfig = @{
    Title  = "Welcome. Please select an option:"
    Options = @(
        @{
            Name     = "Dog Breeds"
            FilePath = ".\Requests\DogBreeds.request.xml"
        },
        @{
            Name     = "Dog Breeds Random Image"
            FilePath = ".\Requests\DogBreedsRandomImage.request.xml"
        },        
        @{
            Name     = "List Of Continents By Name"
            FilePath = ".\Requests\ListOfContinentsByName.request.xml"
        },
        @{
            Name     = "Capital City of a Country"
            FilePath = ".\Requests\CapitalCity.request.xml"
        },        
        @{
            Name     = "Ron Swanson Quotes"
            FilePath = ".\Requests\ron-swanson-quotes.request.xml"
        },
        @{
            Name     = "Alert Hub Authenticate"
            FilePath = ".\Requests\AlertHubAuthenticate.request.xml"
        },
        @{
            Name     = "Alert Hub Delivery Basic APNS Message"
            FilePath = ".\Requests\AlertHubDeliveryMessage.request.xml" 
        },
        @{
            Name     = "Alert Hub Notification Status"
            FilePath = ".\Requests\AlertHubNotificationStatus.request.xml" 
        }                 		
    )
    
    Header = $asciiArt -split "`r?`n"
}
