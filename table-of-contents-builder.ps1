<# .DESCRIPTION
This script collects headers and subheaders from all .md files in subfolders
into a single readme.md as a summary of all posts or a table of contents.
#>

# re-create readme.md
$readmeToc = ".\readme.md"
Set-Content -Path $readmeToc -Value "# Table of Contents`n`n---`n`n"

# get the list of all readme.md files
$readmeFiles = Get-ChildItem -Path . -Filter "readme.md" -Recurse

foreach ($readmeFile in $readmeFiles) {

  # ignore the ToC file
  if ($readmeFile.Directory.FullName -eq $PSScriptRoot) { continue }

  # read the top few lines
  $text = Get-Content $readmeFile.FullName -TotalCount 5

  # reset output vars
  $title = ""
  $subtitle = ""

  # loop through read lines
  foreach ($line in $text) {

    # match the first level 1 title
    if ($line -match "^\s*#\s+(.+)") {
      if ($title -eq "") {
        $title = $Matches.1
      }
    }

    # match the first level 4 title and break the loop
    if ($line -match "^\s*####\s+(.+)") {
      if ($subtitle -eq "") {
        $subtitle = $Matches.1
        break 
      }
    }
  }
  
  # ignore files with no title
  if ($title -eq "") { continue }

  # prepare a relative URL
  $url = $readmeFile.FullName.Replace($PSScriptRoot, "")
  $url = $url.Replace("\", "/") # a windows thing
  $url = $url.Replace("readme.md", "") # kill the file name from the path
  $url = $url.Substring(1) # remove the leading /

  # build the output per post
  $tocItem = "## [$title]($url)" # create level 1 link
  if ($subtitle -ne "") { $tocItem += "`n> " + $subtitle } # re-create level 4 subtitle
  $tocItem += "`n`n" # space them out
  
  # add to ToC
  Add-Content -Path $readmeToc -Value $tocItem
}