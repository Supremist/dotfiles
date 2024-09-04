<#
.SYNOPSIS
    Dotfiles bootstrap script.
.DESCRIPTION
    This script will ensure installation of Scoop, Git and Nushell, prior to cloning dotfiles repo.
.PARAMETER Url
    Url of this file on github. Will be parsed to extract username, repo and branch.
.PARAMETER ScoopDir
    Specifies Scoop root path.
    If not specified, Scoop will be installed to '$env:SystemDrive\scoop'.
.PARAMETER GitDir
    Directory, where dotfiles repo will be located.
    If not specified, defaults to '~\.dotfiles'
#>
param(
    [Parameter(Mandatory=$true)] [System.Uri] $Url,
    [String] $ScoopDir,
    [String] $GitDir = "~\.dotfiles"
)

function Main {
    $ErrorActionPreference = "Stop"
    $GitDir = $GitDir -replace '^~', $env:USERPROFILE
    
    if (Test-Path $GitDir) {
        Write-Host "Dotfiles dir already exists"
        return
    }
    cd $env:USERPROFILE
 
    $need_install = @()
    $need_install += Need-Package nu
    $need_install += Need-Package git mingit
    $need_scoop = Need-Package scoop
    
    if ($ScoopDir) {
        $ScoopDir = $ScoopDir -replace '^~', $env:USERPROFILE
        if (-not $need_scoop) {
            Write-Host "Ignoring ScoopDir. Scoop already installed."
        }
    } else {
        $ScoopDir = "$env:SystemDrive\scoop"
    }
    
    if ($need_install) {
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
        if ($need_scoop) {
            Install-Scoop $ScoopDir
        }
        
        scoop install $need_install
        if (($LASTEXITCODE -ne 0) -or -not (Get-Command nu -ErrorAction Ignore)) {
            throw "Failed to install: $need_install. Exit code: $LASTEXITCODE"
        }
    } elseif ($need_scoop) {
        Write-Host "Scoop installation postponed... Seting SCOOP env var"
        $env:SCOOP = $ScoopDir
        [Environment]::SetEnvironmentVariable("SCOOP", "$ScoopDir", "User")
    }
    
    $env:GIT_WORK_TREE = $env:USERPROFILE
    $env:GIT_DIR = $GitDir

    $username = $Url.Segments[1].Trim('/')
    $repo = $Url.Segments[2].Trim('/')
    $branch = $Url.Segments[3].Trim('/')

    $next_stage = "02-initial-checkout.nu"
    $next_stage_file = "$env:USERPROFILE\$next_stage"
    $utf8_no_bom = New-Object System.Text.UTF8Encoding $False
    
    git clone --bare "https://github.com/$username/$repo.git" "$env:GIT_DIR"
    $stage_data = git show "${branch}:scripts/install/$next_stage"
    [System.IO.File]::WriteAllLines($next_stage_file, $stage_data, $utf8_no_bom)
    nu "$next_stage_file" "$branch"
    nu -e "rm $next_stage_file"
}

function Install-Scoop {
    param([String] $Location)
    Write-Host "Installing Scoop..."
    iex "& {$(irm get.scoop.sh)} -ScoopDir '$Location'"

    # TODO remove scoop dir from user path, add it to system path
    scoop install aria2 # will speed up downloads
}

function Need-Package {
    param(
        [String] $BinName, 
        [String] $Package = $BinName
    )
    $cmd = Get-Command $BinName -ErrorAction Ignore
    if ($?) {
        Write-Host "Found '$BinName' command at '$($cmd.Source)'"
    } else {
        return $Package
    }
}

Main