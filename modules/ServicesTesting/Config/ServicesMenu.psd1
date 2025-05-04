@{
    CategoryNames = @{
        SBI = "Standard Banking Interface"
        VOY = "Voyager Services"
        ALE = "Alert Services"
        REG = "Registration Services"
        RCS = "Rich Channel Services"
        MFH = "MFHost Services"
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
