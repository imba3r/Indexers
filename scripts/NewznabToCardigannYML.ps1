#Requires -Version 7 -Modules powershell-yaml

<#
    .SYNOPSIS
        Name: Invoke-NewznabToCardigannYML.ps1
        The purpose of this script is to convert a Newznab response and generate a Cardigann compatible YML definition
    .DESCRIPTION
        Ingests a given Usenet Indexer that follows the Newznab standard (APIKey optional; site dependent) and outputs a named Cardigann YML
    .NOTES
        This script has been tested on Windows PowerShell 7.1.3
    .EXAMPLE
    PS> .\NewznabToCardigannYML.ps1 -site https://nzbplanet.net -apikey "SomeKey" -indexer "nzbplanet"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, Position = 0)]
    [string]$site,
    [Parameter(Position = 1)]
    [string]$indexer,
    [Parameter(Position = 2)]
    [string]$privacy
)

# Generate Caps Call
[string]$capsCall = ($site + '/api?t=caps')


function Invoke-NameReplace {
    param (
        [Parameter(Mandatory)]
        [string]
        $Name
    )
    return ($Name -replace 'xbox', 'XBox' -replace 'ebook', 'EBook' -replace 'XBox One', 'XBox One' -replace 'WiiWare/VC', 'Wiiware' -replace 'Pc', 'PC')
}

# Get Data and digest objects
[xml]$xmlResponse = (Invoke-WebRequest -Uri $capscall -Headers $headers -ContentType 'application/xml' -Method Get).Content
$rSearchCaps = $xmlResponse.caps.searching
$rCategories = $xmlResponse.caps.categories.category

# Caps
[string]$q_search = "[$($rSearchCaps.search.supportedParams -replace ",",", ")]"
[string]$movie_search = "[$($rSearchCaps.'movie-search'.supportedParams -replace ",",", ")]"
[string]$tv_search = "[$($rSearchCaps.'tv-search'.supportedParams -replace ",",", ")]"
[string]$book_search = "[$($rSearchCaps.'book-search'.supportedParams -replace ",",", ")]"
[string]$audio_search = "[$($rSearchCaps.'audio-search'.supportedParams -replace ",",", ")]"

# Get Main Categories: ID, Name
[System.Collections.Generic.List[System.Object]]$categories = @()

foreach ($category in $rCategories)
{
    $catName = Invoke-NameReplace -Name $category.name
    $temp = [PSCustomObject][ordered]@{
        id = $category.id
        cat = $catName
        desc = $category.description
    }
    $categories.Add($temp)
}

foreach ($category in $rCategories.subcat)
{
    $catName = Invoke-NameReplace -Name "$($category.description)/$($category.name)"
    $temp = [PSCustomObject][ordered]@{
        id = $category.id
        cat = $catName
        desc = $category.description
    }
    $categories.Add($temp)
}

[System.Collections.Generic.List[string]]$ymlCategories = @()
foreach ($category in ($categories | Sort-Object id))
{
    # TODO: This is currently causing the output to be a list of strings
    $ymlCategories.Add("{ id: $($category.id), cat: $($category.cat), desc: $($category.desc) }")
}

# ToDo: Validate Categories List (Names) - use newznabcats.txt
# None matching categories (case insensitive) will need to be commented out

#TODO: This is currently creating strings for each mode and these shouldn't be strings
$modes = [ordered]@{
    search = $q_search
}

if ($tv_search -ne "[]")
{
    $modes['tv-search'] = $tv_search
}
if ($movie_search -ne "[]")
{
    $modes['movie-search'] = $movie_search
}
if ($book_search -ne "[]")
{
    $modes['book-search'] = $book_search
}
if ($audio_search -ne "[]")
{
    $modes['audio-search'] = $audio_search
}

#TODO: Finish this off with some if statements as per modes
$inputs = [ordered]@{
    t = "{{ .Query.Type }}"
    apikey = "{{ .Config.apikey }}"
    q = "{{ .Keywords }}"
}

$hashTable = [ordered]@{
    id = "$($xmlResponse.caps.server.title)-yml"
    name = $($xmlResponse.caps.server.title)
    description = "$($xmlResponse.caps.server.title) is a $privacy Usenet Indexer"
    language = "en-us"
    type = $privacy
    allowdownloadredirect = $true
    protocol = "usenet"
    encoding = "UTF-8"
    links = @($xmlResponse.caps.server.url)
    caps = [ordered]@{
        categorymappings = $ymlCategories
        modes = $modes
    }
    settings = @(
        [ordered]@{
            name = "apikey"
            type = "text"
            label = "Site API Key"
        }
    )
    search = [ordered]@{
        ignoreblankinputs = $true
        paths = @(
            @{
                path = "/api/"
                response = @{
                    type = "xml"
                    attribute = "attributes"
                }
            }
        )
        error = @(
            @{
                selector = "error"
                message = @{
                    selector = "error"
                    attribute = "description"
                }
            }
        )
        inputs = $inputs
        rows = @{
            selector = "rss > channel > item"
        }
        fields = [ordered]@{
            title = @{
                selector = "title"
            }
            details = @{
                selector = "comments"
            }
            date = @{
                selector = "pubDate"
            }
            download = @{
                selector = "link"
            }
            description = @{
                selector = "description"
            }
            tvbdid = @{
                selector = "tvdbid"
            }
            imdbid = @{
                selector = "imdb"
            }
            tmdbid = @{
                selector = "tmdb"
            }
            traktid = @{
                selector = "traktid"
                optional = $true
            }
            genre = @{
                selector = "genre"
                optional = $true
            }
            year = @{
                selector = "year"
                optional = $true
            }
            category = @{
                selector = 'attr[name="category"]:nth-of-type(1)'
                attribute = "value"
            }
            <# CANNOT HAVE DUPLICATE KEYS IN HASHTABLE VALUE - MAY NEED SOME MANUAL BAKER INPUT, alternatively we can just make all this yml and append it as a string
            category = @{
                optional = $true
                selector = 'attr[name="category"]:nth-of-type(2)'
                attribute = "value"
            } #>
            size = @{
                selector = 'attr[name="size"]'
                attribute = "value"
            }
            grabs = @{
                selector = 'attr[name="grabs"]'
                attribute = "value"
            }
            poster = @{
                selector = 'attr[name="poster"]'
                attribute = "value"
            }
            files = @{
                selector = 'attr[name="files"]'
                attribute = "value"
                optional = $true
            }
            coverurl = @{
                selector = 'attr[name="coverurl"]'
                attribute = "value"
            }
        }
    }
    download = @{
        error = @(
            @{
                selector = "error"
                message = @{
                    selector = "error"
                    attribute = "description"
                }
            }
        )
    }
}

return ($hashTable | ConvertTo-Yaml)
