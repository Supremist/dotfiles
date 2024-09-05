# This will launch new powershell as admin, if not currently running as admin already
# Source: https://learn.microsoft.com/en-us/archive/blogs/virtual_pc_guy/a-self-elevating-powershell-script

function Start-PshProcess {
    param(
    [Parameter(Mandatory=$false)] [string]$Verb = "Open",
    [Parameter(Mandatory=$false)] [string]$Dir,
    [Parameter(Mandatory=$true)]  [string]$Cmd,
    [Parameter(Mandatory=$false)] [string[]]$Args = @()
    )
    
    if(-not $Dir) {
        $Dir = Get-Location
    }
    
    $Command = @"
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process; cd "$Dir"; & "$Cmd" $Args
"@

    Write-Host $Command
    Start-Process -FilePath powershell.exe -Verb $Verb -ArgumentList '-NoExit', '-Command', $Command
}

function Is-Admin {
     # Get the ID and security principal of the current user account
    $myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
      
    # Get the security principal for the Administrator role
    $adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
      
    # Check to see if we are currently running "as Administrator"
    return $myWindowsPrincipal.IsInRole($adminRole)
}

function Elevate-Shell {
    param(
        $Invocation,
        $PauseFor = 5
    )
    
    if (-not (Is-Admin)) {
        # We are not running "as Administrator" - so relaunch as administrator
        Write-Host "Starting elevated powershell process..."
        Start-PshProcess -Verb RunAs -Cmd "$($Invocation.MyCommand.Path)" -Args $Invocation.UnboundArguments
        
        Start-Sleep -Seconds $PauseFor
        # Exit from the current, unelevated, process
        exit
    }
}