
$DividerLine = "---" # Divider line

# Menu Configuration
$servicesMenu = @{
    Title  = "Welcome. Please select an option:"
    DividerLine = "---"
    Options = @(
        @{
            Name     = "TST - Dog Breeds"
            FilePath = "Requests\TST\DogBreeds.request.xml"
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
    
}