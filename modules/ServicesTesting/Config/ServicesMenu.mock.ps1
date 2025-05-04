param (
    [string]$ProfileName = "All",
    [string]$DividerLine = "---",
    [string]$SubTitlePrefix = ">"
)


# Nombres largos por categoría
$CategoryNames = @{
    SBI = "Security and Banking Interface"
    VOY = "Voyager Services"
    ALE = "Alert Engine"
    REG = "Registration"
    RCS = "Remote Control System"
    MFH = "Message Forwarding Hub"
    ALH = "Alert Hub"
    TST = "Test Services"
}

# Asociación de perfiles con categorías
$ProfileCategories = @{
    Web = @("RCS", "MFH", "TST")
    App = @("SBI", "VOY", "ALE", "REG", "MFH", "ALH")
    TP  = @("SBI", "VOY")
    All = @("SBI", "VOY", "ALE", "REG", "RCS", "MFH", "ALH", "TST")
}

# Ítems por categoría
$categoryItems = @{
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

# Generar lista completa de ítems como [pscustomobject]
$allMenuItems = foreach ($category in $categoryItems.Keys) {
    foreach ($filename in $categoryItems[$category]) {
        [pscustomobject]@{
            Name     = "$($filename -replace '\.request\.xml$', '')"
            FilePath = ".\Requests\$category\$filename"
            Category = $category
        }
    }
}

# Plantilla del separador como objeto completo
$DividerItem = [pscustomobject]@{
    Name     = $DividerLine
    FilePath = ""
    Category = "Divider"
}

# Construcción del menú
$options = foreach ($category in $ProfileCategories[$ProfileName]) {
    $items = $allMenuItems | Where-Object { $_.Category -eq $category }
    if ($items.Count -gt 0) {
        $longName = $CategoryNames[$category]
        if (-not $longName) { $longName = $category }

        [pscustomobject]@{
            Name     = ">$longName"
            FilePath = ""
        }

        $DividerItem
        $items
        $DividerItem
    }
}

# Quitar separador final si lo hay
if ($options[-1].Category -eq "Divider") {
    #$options = $options[0..($options.Count - 2)]
}

# Estructura final del menú
$servicesMenu = @{
    Title          = "Welcome. Please select an option:"
    DividerLine    = $DividerLine
    SubTitlePrefix = $SubTitlePrefix
    Options        = $options
}

return $servicesMenu
