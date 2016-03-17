<#
.SYNOPSIS
Extracts the schemas from the latest release of the v.Nu .jar on GitHub.

.DESCRIPTION
This script:
1. Uses the GitHub API to get the tag name of the latest v.Nu release
2. Uses the tag name to build a URL to download the latest v.Nu JAR .zip
3. Downloads the release .zip
4. Extracts the .jar from the .zip
5. Extracts the schemas from the .jar into the directory structure used by v.Nu

Requires:
-  PowerShell 4, or later
-  7-Zip (http://www.7-zip.org/)

.PARAMETER Destination
The path of the output directory for the schemas.
If omitted, the schemas are output to a vnu-schema directory under the current directory.
If the output directory already exists, it is deleted before being written to.

.EXAMPLE
C:\PS> .\Get-vnu-Schemas.ps1 c:\temp\vnu-schema

.INPUTS
- The v.Nu GitHub repo (validator/validator)
- The unsoup/validator GitHub repo

.OUTPUTS
Outputs v.Nu schemas in the same directory structure used by v.Nu.

.LINK
https://github.com/unsoup/validator
#>

# Copyright (c) 2016 Graham Hannington

# To do:
# -  Replace Out-Null with something that remains silent except on error

[CmdletBinding()]
Param(
  [Parameter(Mandatory=$False,Position=1)]
  [string] $Destination = (Join-Path $Pwd "vnu-schema")
)

# Functions

<#
.SYNOPSIS
Copies file, creating destination directory path if it does not exist
#>
function Copy-New-Item {
  Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string] $SourceFilePath,
    
    [Parameter(Mandatory=$True,Position=2)]
    [string] $DestinationFilePath
  )

  If (-not (Test-Path $DestinationFilePath)) {
    New-Item -ItemType File -Path $DestinationFilePath -Force | Out-Null
  } 
  Copy-Item -Path $SourceFilePath -Destination $DestinationFilePath | Out-Null
}

<#
.SYNOPSIS
Uses GitHub API to get tag name of latest release of a repo
#>
function Get-GitHub-Repo-Latest-Release-Tag {
  Param(
    [Parameter(Mandatory=$true)]
    # Repository owner
    [string] $Owner,
    
    [Parameter(Mandatory=$true)]
    # Repository name
    [string] $Repo
  )
  
  $url = "https://api.github.com/repos/" + $Owner + "/" + $Repo + "/releases/latest"
  
  Return (Invoke-RestMethod $url).tag_name
}

# Main

# Check 7-Zip is installed
# (could also be in "Program Files (x86)" - might cater for this later)
$szPath = "C:\Program Files\7-Zip\7z.exe"
if (-not (test-path $szPath)) {
  throw ($szPath + " required")
}
set-alias sz $szPath

# Identify the v.Nu GitHub repo
$owner = "validator"
$repo = "validator"

$tag = Get-GitHub-Repo-Latest-Release-Tag $owner $repo

# .jar file name without release tag
$vnuJarFileName = "vnu.jar"

$vnuJarZipFileName = $vnuJarFileName + "_" + $tag + ".zip"

# Path of .jar inside release .zip
$vnuJarPathInZip = "dist/" + $vnuJarFileName

# Path of files directory inside .jar
$vnuFilesPathInJar = "nu/validator/localentities/files/*"

# Work subdirectory under temporary directory
$vnuTempDirectoryPath = (Join-Path $env:temp "vnu-schema")

# URL of release .zip to download
$vnuJarZipUrl = "https://github.com/" + $owner + "/" + $repo + "/releases/download/" + $tag + "/" + $vnuJarZipFileName

# Local temporary paths
$vnuJarZipLocalPath = (Join-Path $env:temp $vnuJarZipFileName)
$vnuJarLocalPath = (Join-Path $vnuTempDirectoryPath $vnuJarFileName)

# File inside the .jar that lists the schema files
$entityMapPath = (Join-Path $vnuTempDirectoryPath "entitymap")

# URI in the entitymap that identifies schemas
$schemaUriBase = "http://s.validator.nu/"

# Base URL for getting raw files from a GitHub repo
$rawGitHubUserContentUrlBase = "https://raw.githubusercontent.com/"

# Delete files or directories left behind by previous script that did not complete
if (Test-Path $vnuJarZipLocalPath) {
  Remove-Item $vnuJarZipLocalPath
}
if (Test-Path $vnuTempDirectoryPath) {
  Remove-Item -Recurse -Force $vnuTempDirectoryPath
}

# Download latest vnu.jar release .zip from GitHub
Invoke-WebRequest -Uri $vnuJarZipUrl -OutFile $vnuJarZipLocalPath

# Extract .jar from .zip
sz e "$vnuJarZipLocalPath" "-o$vnuTempDirectoryPath" $vnuJarPathInZip | Out-Null

# Extract files from .jar
sz e "$vnuJarLocalPath" "-o$vnuTempDirectoryPath" $vnuFilesPathInJar | Out-Null

# Delete existing destination folder
if (Test-Path $Destination) {
  Remove-Item -Recurse -Force $Destination
}

# "Unresolve" the entitymap:
# Copy the schema files into a directory structure based on the entity URI
ForEach ($line in Get-Content $entityMapPath) {
  # Split the entitymap line into two fields
  $fields = $line.Split()
  # The first field is the URI
  $uri = $fields[0]
  if ($uri.StartsWith($schemaUriBase)) {
    # The second field is the file name
    $schemaEntityFileName = $fields[1]
    $sourceFilePath = (Join-Path $vnuTempDirectoryPath $schemaEntityFileName)
    # Get relative path of schema file,
    # and replace forward slashes in the URI with Windows-friendly backslashes
    $relativeSchemaFilePath = $uri.Substring($schemaUriBase.length).Replace("/", "\")
    $destinationFilePath = (Join-Path $Destination $relativeSchemaFilePath)
    Copy-New-Item $sourceFilePath $destinationFilePath
	}
}

# Download license files from v.Nu GitHub repo to destination directory
# The general license for v.Nu
Invoke-WebRequest `
  -Uri ($rawGitHubUserContentUrlBase + "validator/validator/master/LICENSE") `
  -OutFile (Join-Path $Destination "LICENSE")
# The specific license for the (X)HTML schemas
Invoke-WebRequest `
  -Uri ($rawGitHubUserContentUrlBase + "validator/validator/master/schema/html5/LICENSE") `
  -OutFile (Join-Path $Destination "html5\LICENSE")

# Download readme from unsoup/validator/schema-release GitHub repo to destination directory
Invoke-WebRequest `
  -Uri ($rawGitHubUserContentUrlBase + "unsoup/validator/gh-pages/README.md") `
  -OutFile (Join-Path $Destination "README.md")

# Delete temporary directory and files
Remove-Item $vnuJarZipLocalPath
Remove-Item -Recurse -Force $vnuTempDirectoryPath