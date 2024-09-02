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
    [String] $ScoopDir = "$env:SystemDrive\scoop",
    [String] $GitDir = "~\.dotfiles"
)


# config
$ErrorActionPreference = "Stop"
$ScoopDir = $ScoopDir -replace '^~', $env:USERPROFILE
$GitDir = $GitDir -replace '^~', $env:USERPROFILE

$env:GIT_WORK_TREE = $env:USERPROFILE
$env:GIT_DIR = $GitDir

$username = $Url.Segments[1].Trim('/')
$repo = $Url.Segments[2].Trim('/')
$branch = $Url.Segments[3].Trim('/')


function Install-Scoop {
    Write-Host "Installing Scoop..."
    iex "& {$(irm get.scoop.sh)} -ScoopDir '$ScoopDir'"

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

function Main {
    if (Test-Path $env:GIT_DIR) {
        Write-Host "Dotfiles dir already exists"
        return
    }
    cd $env:USERPROFILE
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
    
    $need_install = @()
    $need_install += Need-Package nu
    $need_install += Need-Package git mingit
    
    if ($need_install) {
        if (Need-Package scoop) {
            Install-Scoop
        }
        scoop install $need_install
        if (($LASTEXITCODE -ne 0) -or -not (Get-Command nu -ErrorAction Ignore)) {
            throw "Failed to install: $need_install. Exit code: $LASTEXITCODE"
        }
    }

    $next_stage = "02-initial-checkout.nu"
    $next_stage_file = "$env:USERPROFILE\$next_stage"
    $utf8_no_bom = New-Object System.Text.UTF8Encoding $False
    
    git clone --bare "https://github.com/$username/$repo.git" "$env:GIT_DIR"
    $stage_data = git show "${branch}:scripts/install/$next_stage"
    [System.IO.File]::WriteAllLines($next_stage_file, $stage_data, $utf8_no_bom)
    nu "$next_stage_file" "$branch"
    nu -e "rm $next_stage_file"
}

Main