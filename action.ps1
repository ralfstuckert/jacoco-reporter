#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

## Make sure any modules we depend on are installed
$modulesToInstall = @(
    'GitHubActions'
)

$modulesToInstall | ForEach-Object {
    if (-not (Get-Module -ListAvailable -All $_)) {
        Write-Output "Module [$_] not found, INSTALLING..."
        Install-Module $_ -Force
    }
}

## Import dependencies
Import-Module GitHubActions -Force

Write-ActionInfo "Running from [$($PSScriptRoot)]"

function splitListInput { $args[0] -split ',' | % { $_.Trim() } }
function writeListInput { $args[0] | % { Write-ActionInfo "    - $_" } }

$inputs = @{
    coverage_report_name = Get-ActionInput coverage_report_name
    coverage_report_title = Get-ActionInput coverage_report_title
    coverage_results_path = Get-ActionInput coverage_results_path -Required
    github_token       = Get-ActionInput github_token -Required
    skip_check_run     = Get-ActionInput skip_check_run
}

$test_results_dir = Join-Path $PWD _TMP
Write-ActionInfo "Creating test results space"
mkdir $test_results_dir
Write-ActionInfo $test_results_dir
$script:coverage_report_path = Join-Path $test_results_dir coverage-results.md

function Build-CoverageReport {
    Write-ActionInfo "Building human-readable code-coverage report"
    $script:coverage_report_name = $inputs.coverage_report_name
    $script:coverage_report_title = $inputs.coverage_report_title

    if (-not $script:coverage_report_name) {
        $script:coverage_report_name = "COVERAGE_RESULTS_$([datetime]::Now.ToString('yyyyMMdd_hhmmss'))"
    }
    if (-not $coverage_report_title) {
        $script:coverage_report_title = $report_name
    }

    $script:coverage_report_path = Join-Path $test_results_dir coverage-results.md
    & "$PSScriptRoot/jacoco-report/jacocoxml2md.ps1" -Verbose `
        -xmlFile $script:coverage_results_path `
        -mdFile $script:coverage_report_path -xslParams @{
            reportTitle = $script:coverage_report_title
        }

   & "$PSScriptRoot/jacoco-report/embedmissedlines.ps1"
}


function Publish-ToCheckRun {
    param(
        [string]$reportData,
        [string]$reportName,
        [string]$reportTitle
    )

    Write-ActionInfo "Publishing Report to GH Workflow"

    $ghToken = $inputs.github_token
    $ctx = Get-ActionContext
    $repo = Get-ActionRepo
    $repoFullName = "$($repo.Owner)/$($repo.Repo)"

    Write-ActionInfo "Resolving REF"
    $ref = $ctx.Sha
    if ($ctx.EventName -eq 'pull_request') {
        Write-ActionInfo "Resolving PR REF"
        $ref = $ctx.Payload.pull_request.head.sha
        if (-not $ref) {
            Write-ActionInfo "Resolving PR REF as AFTER"
            $ref = $ctx.Payload.after
        }
    }
    if (-not $ref) {
        Write-ActionError "Failed to resolve REF"
        exit 1
    }
    Write-ActionInfo "Resolved REF as $ref"
    Write-ActionInfo "Resolve Repo Full Name as $repoFullName"

    Write-ActionInfo "Adding Check Run"
    $url = "https://api.github.com/repos/$repoFullName/check-runs"
    $hdr = @{
        Accept = 'application/vnd.github.antiope-preview+json'
        Authorization = "token $ghToken"
    }
    $bdy = @{
        name       = $reportName
        head_sha   = $ref
        status     = 'completed'
        conclusion = 'neutral'
        output     = @{
            title   = $reportTitle
            summary = "This run completed at ``$([datetime]::Now)``"
            text    = $ReportData
        }
    }
    Invoke-WebRequest -Headers $hdr $url -Method Post -Body ($bdy | ConvertTo-Json)
}

if ($inputs.skip_check_run -ne $true) 
    {
        Write-ActionInfo "Publishing Report to GH Workflow"    
        $coverage_results_path = $inputs.coverage_results_path
        $coverageXmlData = Select-Xml -Path $coverage_results_path -XPath "/report/counter[@type='LINE']"
        $coveredLines = $coverageXmlData.Node.covered
        Write-Host "Covered Lines: $coveredLines"
        $missedLines = $coverageXmlData.Node.missed
        Write-Host "Missed Lines: $missedLines"
        if ($missedLines -eq 0) 
            {
            $coveragePercentage = 100
            } 
        else 
            {
            $coveragePercentage = [math]::Round(100 - (($missedLines / $coveredLines) * 100))
            }
        $coveragePercentageString = "$coveragePercentage%"
        Write-Output $coveragePercentageString
        Set-ActionOutput -Name coverage_results_path -Value $coverage_results_path
        Build-CoverageReport
        $coverageSummaryData = [System.IO.File]::ReadAllText($coverage_report_path)
        Publish-ToCheckRun -ReportData $coverageSummaryData -ReportName $coverage_report_name -ReportTitle $coverage_report_title
    }
