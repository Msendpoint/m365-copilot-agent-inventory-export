<#
.SYNOPSIS
    Exports a full inventory of Microsoft 365 Copilot agents and identifies third-party agents for governance review.

.DESCRIPTION
    This script connects to Microsoft Graph using the required scopes and retrieves all
    Teams apps distributed within the organization. Since Copilot agents surface as Teams
    apps under the hood, this provides a complete baseline inventory of deployed agents.
    The results are exported to a timestamped CSV file, and third-party agents (those not
    published by Microsoft) are identified and displayed in a summary table.

    Use this script before making any governance changes to establish a baseline, and
    re-run it periodically as part of a repeatable Copilot agent governance framework.

.PARAMETER ExportPath
    The directory path where the CSV inventory file will be saved.
    Defaults to C:\Temp.

.PARAMETER MicrosoftExternalIdPrefix
    The prefix used to identify Microsoft-published agents via their ExternalId.
    Defaults to '^com\.microsoft'.

.EXAMPLE
    .\Export-CopilotAgentInventory.ps1

    Connects to Microsoft Graph, exports all org-distributed Teams apps (Copilot agents)
    to C:\Temp\AgentInventory_<yyyyMMdd>.csv, and displays a summary of third-party agents.

.EXAMPLE
    .\Export-CopilotAgentInventory.ps1 -ExportPath 'D:\Reports'

    Exports the agent inventory CSV to D:\Reports instead of the default C:\Temp.

.NOTES
    Author       : M365 Governance Automation
    Version      : 1.0.0
    Requires     : Microsoft.Graph PowerShell SDK
                   AppCatalog.Read.All and TeamsApp.Read.All Graph API permissions
    Roles        : Global Administrator or Teams Administrator
    License      : MIT

    Install the Microsoft Graph SDK if not already present:
        Install-Module Microsoft.Graph -Scope CurrentUser -Force
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = 'Directory path for the exported CSV file.')]
    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = 'C:\Temp',

    [Parameter(Mandatory = $false, HelpMessage = 'Regex prefix to identify Microsoft-published agents by ExternalId.')]
    [string]$MicrosoftExternalIdPrefix = '^com\.microsoft'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Dependency Check ---
Write-Verbose 'Checking for Microsoft.Graph module...'
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    throw 'The Microsoft.Graph PowerShell SDK is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser -Force'
}
#endregion

#region --- Ensure Export Directory Exists ---
if (-not (Test-Path -Path $ExportPath)) {
    Write-Verbose "Export path '$ExportPath' does not exist. Creating it..."
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}
#endregion

#region --- Connect to Microsoft Graph ---
Write-Host '🔐 Connecting to Microsoft Graph...' -ForegroundColor Cyan
try {
    Connect-MgGraph -Scopes 'AppCatalog.Read.All', 'TeamsApp.Read.All' -ErrorAction Stop
    Write-Host '✅ Connected to Microsoft Graph successfully.' -ForegroundColor Green
}
catch {
    throw "Failed to connect to Microsoft Graph: $_"
}
#endregion

#region --- Retrieve All Org-Distributed Teams Apps (Copilot Agents) ---
Write-Host '📋 Retrieving all organization-distributed Teams apps (Copilot agents)...' -ForegroundColor Cyan
try {
    $agents = Get-MgAppCatalogTeamApp `
        -Filter "distributionMethod eq 'organization'" `
        -All `
        -ErrorAction Stop
}
catch {
    throw "Failed to retrieve Teams apps from Microsoft Graph: $_"
}

$totalCount = $agents.Count
Write-Host "Total agents found: $totalCount" -ForegroundColor Yellow
#endregion

#region --- Export Full Inventory to CSV ---
$timestamp   = Get-Date -Format 'yyyyMMdd'
$csvFileName = "AgentInventory_$timestamp.csv"
$csvPath     = Join-Path -Path $ExportPath -ChildPath $csvFileName

Write-Host "💾 Exporting full agent inventory to: $csvPath" -ForegroundColor Cyan
try {
    $agents |
        Select-Object DisplayName, Id, ExternalId, DistributionMethod |
        Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "✅ Inventory exported successfully: $csvPath" -ForegroundColor Green
}
catch {
    throw "Failed to export inventory CSV: $_"
}
#endregion

#region --- Identify Third-Party Agents ---
Write-Host '' 
Write-Host '🔍 Identifying third-party agents (not published by Microsoft)...' -ForegroundColor Cyan

$thirdPartyAgents = $agents | Where-Object {
    $_.ExternalId -notmatch $MicrosoftExternalIdPrefix
}

$thirdPartyCount = $thirdPartyAgents.Count
Write-Host "Third-party agents found: $thirdPartyCount" -ForegroundColor Yellow

if ($thirdPartyCount -gt 0) {
    Write-Host '' 
    Write-Host '⚠️  Third-Party Agent Summary (review before approving):' -ForegroundColor Magenta
    $thirdPartyAgents |
        Select-Object DisplayName, ExternalId, Id |
        Format-Table -AutoSize
}
else {
    Write-Host '✅ No third-party agents detected.' -ForegroundColor Green
}
#endregion

#region --- Summary ---
Write-Host ''
Write-Host '========================================' -ForegroundColor DarkGray
Write-Host ' Copilot Agent Inventory Summary' -ForegroundColor White
Write-Host '========================================' -ForegroundColor DarkGray
Write-Host "  Total agents inventoried : $totalCount"
Write-Host "  Third-party agents found : $thirdPartyCount"
Write-Host "  Export location          : $csvPath"
Write-Host '========================================' -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Next Steps:' -ForegroundColor Cyan
Write-Host '  1. Review the CSV and classify each agent as Approved, Restricted, or Blocked.'
Write-Host '  2. Block unvetted third-party agents via M365 Admin Center → Settings → Integrated Apps.'
Write-Host '  3. Apply Teams app permission policies for granular Copilot agent access control.'
Write-Host ''
#endregion
