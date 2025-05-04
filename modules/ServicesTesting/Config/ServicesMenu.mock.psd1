@{
    CategoryNames = @{
        SBI = "Security and Banking Interface"
        VOY = "Voyager Services"
        ALE = "Alert Engine"
        REG = "Registration"
        RCS = "Remote Control System"
        MFH = "Message Forwarding Hub"
        ALH = "Alert Hub"
        TST = "Test Services"
    }

    ProfileCategories = @{
        Web = @("RCS", "MFH", "TST")
        App = @("SBI", "VOY", "ALE", "REG", "MFH", "ALH")
        TP  = @("SBI", "VOY")
    }

    CategoryItems = @{
        TST = @(
            "DogBreeds.request.xml",
            "DogBreedsRandomImage.request.xml",
            "ListOfContinentsByName.request.xml",
            "CapitalCity.request.xml",
            "ron-swanson-quotes.request.xml"
        )
        ALH = @(
            "AlertHubAuthenticate.request.xml",
            "AlertHubDeliveryMessage.request.xml",
            "AlertHubNotificationStatus.request.xml"
        )
    }
}
