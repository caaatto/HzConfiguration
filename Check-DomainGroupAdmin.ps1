<#
.SYNOPSIS
    Robust check: verifies if a Domain group is a member of the local "Administrators" group
    (CIM -> ADSI -> net localgroup fallbacks). Also reports if the current user has admin rights.

.DESCRIPTION
    This script uses multiple fallback methods to reliably determine local Administrators group membership:
    1. CIM/WMI (Win32_Group + Associators) - preferred method
    2. ADSI (WinNT provider) - first fallback
    3. net localgroup - last resort fallback

    Useful for pre-deployment checks to verify group membership before making system changes.

.PARAMETER DomainGroup
    Group in format "DOMAIN\Group". Default: 'EGV\W10_AD_WS_LEHRLINGE'

.PARAMETER LogFile
    Optional path for CSV append log.

.EXAMPLE
    .\Check-DomainGroupAdmin.ps1
    # Checks if default group 'EGV\W10_AD_WS_LEHRLINGE' is in local Administrators

.EXAMPLE
    .\Check-DomainGroupAdmin.ps1 -DomainGroup 'CONTOSO\IT_Admins'
    # Checks if 'CONTOSO\IT_Admins' is in local Administrators

.EXAMPLE
    .\Check-DomainGroupAdmin.ps1 -DomainGroup 'DOMAIN\Group' -LogFile 'C:\Logs\admin-check.csv'
    # Checks group membership and logs result to CSV

.NOTES
    Author: MonitorFix Team
    Version: 1.0
    Requires: Windows PowerShell 5.1 or later
#>

param(
    [string]$DomainGroup = 'EGV\W10_AD_WS_LEHRLINGE',
    [string]$LogFile = ''
)

function Resolve-AccountToSid {
    <#
    .SYNOPSIS
        Resolves an account name to its SID
    #>
    param([string]$accountName)
    if (-not $accountName) { return $null }
    try {
        $nt = New-Object System.Security.Principal.NTAccount($accountName)
        $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier])
        return $sid.Value
    } catch {
        return $null
    }
}

function Get-LocalAdministratorsMembers_Reliable {
    <#
    .SYNOPSIS
        Attempts multiple methods to retrieve members of the local Administrators group.
        Returns array of PSCustomObjects: Name, Domain, Class, SID, Source, Error
    #>
    $out = @()

    # 1) Try CIM/WMI (Win32_Group + Associators)
    try {
        $filter = "LocalAccount=True AND Name='Administrators' AND Domain='$env:COMPUTERNAME'"
        $grp = Get-CimInstance -ClassName Win32_Group -Filter $filter -ErrorAction Stop
        $assocs = Get-CimAssociatedInstance -InputObject $grp -Association Win32_GroupUser -ErrorAction Stop
        foreach ($a in $assocs) {
            # Win32_Account (Win32_UserAccount or Win32_Group)
            $name = if ($a.Domain) { "$($a.Domain)\$($a.Name)" } else { $a.Name }
            $class = $a.__CLASS
            $sid = $null
            try { $sid = Resolve-AccountToSid -accountName $name } catch {}
            $out += [PSCustomObject]@{ Name = $name; Domain = $a.Domain; Class = $class; SID = $sid; Source = 'CIM'; Error = $null }
        }
        if ($out.Count -gt 0) { return $out }
    } catch {
        # Continue to ADSI fallback
        $cimError = $_.Exception.Message
    }

    # 2) ADSI fallback (robust with per-member try/catch)
    try {
        $group = [ADSI]"WinNT://$env:COMPUTERNAME/Administrators,group"
        try {
            $members = $group.PSBase.Invoke("Members")
        } catch {
            throw "ADSI.Invoke('Members') failed: $($_.Exception.Message)"
        }

        foreach ($m in $members) {
            try {
                $adspath = $null
                try { $adspath = $m.ADsPath 2>$null } catch {}
                if ($adspath -and $adspath -match '^WinNT://') {
                    $parts = $adspath -split '/'
                    if ($parts.Count -ge 3) {
                        $domainOrComp = $parts[-2]; $objName = $parts[-1]
                        $name = "$domainOrComp\$objName"
                    } else {
                        $name = $m.GetType().InvokeMember("Name","GetProperty",$null,$m,$null)
                    }
                } else {
                    $name = $m.GetType().InvokeMember("Name","GetProperty",$null,$m,$null)
                }
                $class = $null
                try { $class = $m.GetType().InvokeMember("Class","GetProperty",$null,$m,$null) } catch { $class = 'Unknown' }
                $sid = $null
                try { $sid = Resolve-AccountToSid -accountName $name } catch {}
                $out += [PSCustomObject]@{ Name = $name; Domain = ($domainOrComp -or $env:COMPUTERNAME); Class = $class; SID = $sid; Source = 'ADSI'; Error = $null }
            } catch {
                # Problem with this member: log minimal placeholder with error message
                $memberName = $null
                try { $memberName = $m.GetType().InvokeMember("Name","GetProperty",$null,$m,$null) } catch { $memberName = 'UNKNOWN' }
                $out += [PSCustomObject]@{ Name = $memberName; Domain = $env:COMPUTERNAME; Class = 'Unknown'; SID = $null; Source = 'ADSI'; Error = $_.Exception.Message }
            }
        }

        if ($out.Count -gt 0) { return $out }
    } catch {
        $adsiError = $_.Exception.Message
    }

    # 3) Fallback: 'net localgroup' (as last resort)
    try {
        $raw = & net localgroup Administrators 2>$null
        if ($raw) {
            $lines = $raw | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch 'Alias name|Comment|Members|The command completed|^-+$' }
            foreach ($l in $lines) {
                $name = $l
                $sid = $null
                try { $sid = Resolve-AccountToSid -accountName $name } catch {}
                $out += [PSCustomObject]@{ Name = $name; Domain = ($name -split '\\')[0]; Class = 'Unknown'; SID = $sid; Source = 'net localgroup'; Error = $null }
            }
            if ($out.Count -gt 0) { return $out }
        } else {
            $netError = "No output from 'net localgroup'"
        }
    } catch {
        $netError = $_.Exception.Message
    }

    # If all methods fail: throw comprehensive error with collected info
    $errMsg = "All methods for reading local Administrators members failed."
    $errDetails = @()
    if ($cimError) { $errDetails += "CIM: $cimError" }
    if ($adsiError) { $errDetails += "ADSI: $adsiError" }
    if ($netError) { $errDetails += "NET: $netError" }
    if ($errDetails.Count -gt 0) { $errMsg += " Details: $($errDetails -join ' | ')" }
    throw $errMsg
}

# --- Main ---
$computer = $env:COMPUTERNAME
$timestamp = (Get-Date).ToString('u')
$targetSid = Resolve-AccountToSid -accountName $DomainGroup

try {
    $admins = Get-LocalAdministratorsMembers_Reliable
} catch {
    Write-Error "Error retrieving local Administrators members: $($_.Exception.Message)"
    exit 2
}

# Check if group is present (prefer SID comparison)
$groupPresent = $false
if ($targetSid) {
    foreach ($a in $admins) {
        if ($a.SID -and ($a.SID -eq $targetSid)) { $groupPresent = $true; break }
    }
}
if (-not $groupPresent) {
    $groupShort = $DomainGroup.Split('\')[-1]
    foreach ($a in $admins) {
        if ($a.Name -ieq $DomainGroup -or $a.Name -ieq $groupShort) { $groupPresent = $true; break }
    }
}

# Current user / token info
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$currentUserName = $currentIdentity.Name
$wp = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
$currentIsAdmin = $wp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

# Check if token contains the target SID
$currentMemberOfTarget = $false
if ($targetSid -and $currentIdentity.Groups) {
    $sids = $currentIdentity.Groups | ForEach-Object { $_.Value }
    if ($sids -contains $targetSid) { $currentMemberOfTarget = $true }
}

# Build result object
$result = [PSCustomObject]@{
    Timestamp                       = $timestamp
    Computer                        = $computer
    DomainGroupGiven                = $DomainGroup
    DomainGroupResolvedSID          = (if ($targetSid) { $targetSid } else { '' })
    DomainGroupPresentInLocalAdmins = $groupPresent
    CurrentUser                     = $currentUserName
    CurrentUserIsLocalAdmin         = $currentIsAdmin
    CurrentUserMemberOfDomainGroup  = $currentMemberOfTarget
    LocalAdminsDetail               = ($admins | Select-Object Name,Class,SID,Source,Error)
}

# Optional CSV logging
if ($LogFile -and $LogFile -ne '') {
    try {
        $fields = 'Timestamp','Computer','DomainGroupGiven','DomainGroupResolvedSID','DomainGroupPresentInLocalAdmins','CurrentUser','CurrentUserIsLocalAdmin','CurrentUserMemberOfDomainGroup'
        if (-not (Test-Path $LogFile)) {
            $result | Select-Object $fields | Export-Csv -Path $LogFile -NoTypeInformation
        } else {
            $result | Select-Object $fields | Export-Csv -Path $LogFile -NoTypeInformation -Append
        }
    } catch {
        Write-Warning "Could not write to log file: $($_.Exception.Message)"
    }
}

# Console output (human readable) + detailed problematic entries
Write-Host "=== Local Admin Check ($timestamp) on $computer ==="
Write-Host "Target Group: $DomainGroup"
Write-Host "Group in Administrators? : $groupPresent"
Write-Host "Current User: $currentUserName"
Write-Host "Current User has local Admin rights? : $currentIsAdmin"
Write-Host "Current User member of Target Group? : $currentMemberOfTarget"
Write-Host ""
Write-Host "Local Administrators Members (Source, possible errors):"
foreach ($m in $admins) {
    $err = if ($m.Error) { "ERR:$($m.Error)" } else { "" }
    Write-Host " - $($m.Name) [$($m.Class)] SID:$($m.SID -or 'N/A') Source:$($m.Source) $err"
}
Write-Host "============================================="
return $result
