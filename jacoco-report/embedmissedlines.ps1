
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$mdFile
)

    Write-Output "mdFile is [$mdFile]"

$mdData = Get-Content -Path $mdFile

    Write-Output "mdData is [$mdData]"

$outputData = @()
foreach ($line in $mdData) {
    if ($line -like "- Line #*") {
        $linePrefix = $line.Split("|")[0]
        $lineNumber = $linePrefix.Split("#")[1]
        $arrayLineNumber = $lineNumber - 1

        $filePath = $line.Split("|")[1]
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            $filePath = $filePath.Replace("/","\")
        }
        $workspaceFiles = Get-ChildItem -Path "$env:GITHUB_WORKSPACE" -Recurse -File
        $resolvedFilePath = $workspaceFiles | Where-Object {$_.FullName -like "*$filePath"}
            Write-Output "filePath is [*$filePath]"
            Write-Output "resolvedFilePath is [$resolvedFilePath]"

        $fileContents = Get-Content -Path $resolvedFilePath
        $missedLine = $fileContents[$arrayLineNumber]

        $outputData += $linePrefix
        $outputData += "``````"
        $outputData += $missedLine
        $outputData += "``````"

    }
    else {
        $outputData += $line
    }
}

Set-Content -Value $outputData -Path $mdFile
