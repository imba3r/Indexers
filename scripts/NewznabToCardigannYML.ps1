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
    PS> .\NewznabToCardigannYML.ps1 -site https://nzbplanet.net -indexer "NzbPlanet" -privacy "private" -apipath "/api" -outputfile "C:\Development\Code\Prowlarr_Indexers\definitions\v4\nzbplanet.yml" -language "en-US"
    .EXAMPLE
    PS> .\NewznabToCardigannYML.ps1 -site https://nzbplanet.net -indexer "NzbPlanet" -privacy "public"
    .EXAMPLE
    PS> .\NewznabToCardigannYML.ps1 -site https://nzbplanet.net -indexer "NzbPlanet" -privacy "semi-private"
    .EXAMPLE
    PS> .\NewznabToCardigannYML.ps1 -site https://nzbplanet.net
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, Position = 0)]
    [string]$site,
    [Parameter(Position = 1)]
    [string]$indexer,
    [Parameter(Position = 2)]
    [string]$privacy,
    [Parameter(Position = 3)]
    [string]$apipath = '/api',
    [Parameter(Position = 4)]
    [System.IO.FileInfo]$outputfile = ".$([System.IO.Path]::DirectorySeparatorChar)newznab.yml",
    [Parameter(Position = 4)]
    [string]$language = 'en-US'
)

# Generate Caps Call
[string]$capsCall = ($site + $apipath + '?t=caps')


function Invoke-CatNameReplace
{
    param (
        [Parameter(Mandatory)]
        [string]
        $Name
    )
    return ($Name -replace 'xbox', 'XBox' -replace 'ebook', 'EBook' -replace 'XBox One', 'XBox One' -replace 'WiiWare/VC', 'Wiiware' -replace 'Pc', 'PC' -replace "'", '')
}

function Invoke-ModesReplace
{
    param (
        [Parameter(Mandatory)]
        [string]
        $Name
    )
    return ($Name -replace 'rid', 'TVRageID' -replace 'tmdbid', 'TMDBID' -replace 'tvdbid', 'TVDBID' -replace 'imdbid', 'IMDBIDShort' -replace 'traktid', 'TraktId' -replace 'season', 'Season' -replace 'ep', 'Ep' -replace 'album', 'Album' -replace 'artist', 'Artist' -replace 'label', 'Label' -replace 'genre', 'Genre' -replace 'year', 'Year' -replace 'tvmazeid', 'TVMazeID')
}
function Invoke-YMLReplace
{
    param (
        [Parameter(Mandatory)]
        [string]
        $Name
    )
    return ($Name -replace 'category2', 'category' -replace '"{ ', '{ ' -replace ' }"', ' }' -replace "'{", '{' -replace "}'", '}' -replace '{{', "'{{" -replace '}}', "}}'")
}
# Get Data and digest objects
Write-Information 'Requesting Caps'
[xml]$xmlResponse = Invoke-RestMethod -Uri $capscall -ContentType 'application/xml' -Method Get -StatusCodeVariable "APIResponseCode"
if ($APIResponseCode -ne 200)
{
    throw "The status code $APIResponseCode was received from the website, please investigate why and try again when issue is resolved"
}
$rSearchCaps = $xmlResponse.caps.searching
$rCategories = $xmlResponse.caps.categories.category
$rServer = $xmlResponse.caps.server
Write-Information 'Got Caps'
# Caps
[string]$q_search = "[$($rSearchCaps.search.supportedParams -replace 'group, ',''  -replace ', ',',' )]"
[string]$movie_search = "[$($rSearchCaps.'movie-search'.supportedParams -replace ', ',',')]"
[string]$tv_search = "[$($rSearchCaps.'tv-search'.supportedParams -replace ', ',',')]"
[string]$book_search = "[$($rSearchCaps.'book-search'.supportedParams -replace ', ',',')]"
[string]$audio_search = "[$($rSearchCaps.'audio-search'.supportedParams -replace ', ',',')]"
Write-Information 'Search Caps Built'
# Get Categories: ID, MappedName, Name
Write-Information 'Building Categories'
# TODO: Validate Categories List (Names) - use newznabcats.txt
# None matching categories (case insensitive) will need to be commented out - fuzzy match if possible?
[System.Collections.Generic.List[string]]$ymlCategories = @()
foreach ($category in ($rCategories | Sort-Object id))
{
    $catName = Invoke-CatNameReplace -Name $category.name
    $ymlCategories.Add("{ id: $($category.id), cat: $($catName), desc: $($category.name) }")
    Write-Information "Building Sub-Categories within $($category.id)"
    foreach ($subcategory in ($category.subcat | Sort-Object id))
    {
        $subcatName = Invoke-CatNameReplace -Name "$($catName)/$($subcategory.name)"
        $ymlCategories.Add("{ id: $($subcategory.id), cat: $($subcatName), desc: $($catName)/$($subcategory.name -replace "'", '') }")
    }
}
Write-Information 'Categories Built'
#TODO: This is currently creating strings for each mode and these shouldn't be strings
$modes = [ordered]@{
    search = $q_search
}

if ($tv_search -ne '[]')
{
    $modes['tv-search'] = $tv_search
}
if ($movie_search -ne '[]')
{
    $modes['movie-search'] = $movie_search
}
if ($book_search -ne '[]')
{
    $modes['book-search'] = $book_search
}
if ($audio_search -ne '[]')
{
    $modes['audio-search'] = $audio_search
}

$inputs = [ordered]@{
    t      = '{{ .Query.Type }}'
    apikey = '{{ .Config.apikey }}'
    q      = '{{ .Keywords }}'
}

foreach ($searchinput in ($modes.GETENUMERATOR() | ForEach-Object { $_.VALUE }).Replace('q', '').Replace('[', '').Replace(']', '').Split(',') | Sort-Object)
{
    if ($searchinput -ne 'q' -and $searchinput -ne '')
    {
        #return $searchinput
        [string]$searchstring = $(Invoke-ModesReplace -Name $($searchinput))
        $inputs.Add($($searchinput), "{{ .Query.$($searchstring)}}")
    }
}
Write-Information 'Search Caps converted to YML & Search Inputs created'

$inputs.Add('cat', '{{ join .Categories \", \" }}')
$inputs.Add('raw', '&extended=1')

if (!$indexer)
{
    $indexer = $($rServer.title).replace(' - NZB', '')
}
if ($outputfile.Name -eq 'newznab.yml')
{
    $outputfile = "../definitions/v4/$([System.IO.Path]::DirectorySeparatorChar)$($indexer.Replace(' ','').ToLower()).yml"
}
[string]$indexerstrap = $($rServer.strapline)
[string]$indexerdescr = "'$($indexer) is a $($privacy.ToUpper()) Newznab Usenet Indexer'"
if (!$indexerstrap)
{
    $indexerdescr = $indexerstrap
}
Write-Information 'Building YML'
$hashTable = [ordered]@{
    id                    = "$($indexer.Replace(' ','').ToLower())-yml"
    name                  = $indexer
    description           = $indexerdescr
    language              = $language
    type                  = $privacy.ToLower()
    allowdownloadredirect = $true
    protocol              = 'usenet'
    encoding              = 'UTF-8'
    links                 = @($rServer.url)
    caps                  = [ordered]@{
        categorymappings = $ymlCategories
        modes            = $($modes)
    }
    settings              = @([ordered]@{
            name  = 'apikey'
            type  = 'text'
            label = 'Site API Key'
        }
    )
    search                = [ordered]@{
        ignoreblankinputs = $true
        paths             = @(
            @(    
                [ordered]@{
                    path     = $apipath
                    response = [ordered]@{
                        type      = 'xml'
                        attribute = 'attributes'
                    }
                }
            )
        )
        error             = @(
            @(
                [ordered]@{
                    selector = 'error'
                    message  = [ordered]@{
                        selector  = 'error'
                        attribute = 'description'
                    }
                }
            )
        )
        inputs            = $inputs
        rows              = @{
            selector = 'rss > channel > item'
        }
        fields            = [ordered]@{
            title       = @{
                selector = 'title'
            }
            details     = @{
                selector = 'comments'
            }
            date        = @{
                selector = 'pubDate'
            }
            download    = @{
                selector = 'link'
            }
            description = @{
                selector = 'description'
            }
            tvdbid      = @{
                selector = 'tvdbid'
            }
            imdbid      = @{
                selector = 'imdb'
            }
            tmdbid      = @{
                selector = 'tmdb'
            }
            traktid     = [ordered]@{
                selector = 'traktid'
                optional = $true
            }
            genre       = [ordered]@{
                selector = 'genre'
                optional = $true
            }
            year        = [ordered]@{
                selector = 'year'
                optional = $true
            }
            category    = [ordered]@{
                selector  = 'attr[name="category"]:nth-of-type(1)'
                attribute = 'value'
            }
            category2   = [ordered]@{
                optional  = $true
                selector  = 'attr[name="category"]:nth-of-type(2)'
                attribute = 'value'
            }
            size        = [ordered]@{
                selector  = 'attr[name="size"]'
                attribute = 'value'
            }
            grabs       = [ordered]@{
                selector  = 'attr[name="grabs"]'
                attribute = 'value'
            }
            poster      = [ordered]@{
                selector  = 'attr[name="poster"]'
                attribute = 'value'
            }
            files       = [ordered]@{
                selector  = 'attr[name="files"]'
                attribute = 'value'
                optional  = $true
            }
            coverurl    = [ordered]@{
                selector  = 'attr[name="coverurl"]'
                attribute = 'value'
            }
        }
    }
    download              = [ordered]@{
        error = @(
            @(
                [ordered]@{
                    selector = 'error'
                    message  = [ordered]@{
                        selector  = 'error'
                        attribute = 'description'
                    }
                }
            )
        )
    }
}
Write-Information 'YML Built'

$ymlout = '---
'
$ymlout += (Invoke-YMLReplace -Name $($hashTable | ConvertTo-Yaml))
$ymlout = ($ymlout).replace("'[", '[')
$ymlout = ($ymlout).replace("]'", ']')
$ymlout = ((($ymlout) -replace '\\\\', '\') -replace '---', '---').Trim()
$ymlout += '
# newznab standard'
# return $ymlout

Write-Information 'Indexer YML Complete'
$ymlout | Out-File $OutputFile -Encoding 'UTF-8'
Write-Information 'Indexer YML Page Output - [$OutputFile]'
