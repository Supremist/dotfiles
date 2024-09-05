$ErrorActionPreference = "Stop"

. ~/scripts/lib/Elevate.ps1

Elevate-Shell $MyInvocation

$winget_args = @("--silent", "--accept-package-agreements", "--accept-source-agreements", "--exact")
$msvc_installer_dir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
$msvc_installer_args = @("--passive", "--norestart")


function Install-Winget {
    if (Get-Command winget -ErrorAction Ignore) {
        Write-Host "Found command: winget"
        return
    }
    
    . ~/scripts/lib/MsStore.ps1
    Update-MsStoreApps @("Microsoft.WindowsStore_8wekyb3d8bbwe", "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe") # must contain winget
    if (Get-Command winget -ErrorAction Ignore) { 
        Write-Host "Winget successfully installed."
    } else {
        throw "Failed to install winget!"
    }
}

function Get-VsWhere {
    $cmd = Get-Command vswhere -ErrorAction Ignore
    if ($cmd) {
        return $cmd.Source
    }
    $possible_location = "$msvc_installer_dir\vswhere.exe"
    if (Test-Path $possible_location -PathType Leaf) {
        return $possible_location
    }
    
    Write-Host "Installing vswhere via scoop..."
    scoop install vswhere
    return (Get-Command vswhere).Source
}

function Install-Msvc {
    param(
        [String] $package_id,
        [String] $config_file
    )
    
    winget list --exact --id $package_id | out-null
    $installed_by_winget = $?
    
    $year_to_version = @{'2017' = 15; '2019' = 16; '2022' = 17}
    $parts = $package_id -split "\."
    $year = $parts[2]
    $product = $parts[3]
    $version = $year_to_version[$year]
    if ($version) {
        $next = $version + 1
        $version = @( "-version", "[$version,$next)" )
    } else {
        $version = @()
        Write-Host "WARN Unknown release year in package '$package_id'"
    }
    $vswhere = Get-VsWhere
    $results = & "$vswhere" $version -products "Microsoft.VisualStudio.Product.$product" -sort -format json | ConvertFrom-Json
    if ($results.Length -eq 0) {
        if ($installed_by_winget) {
            throw "Unable to find install location of '$package_id'"
        }
        
        $args = "$msvc_installer_args --config `"$config_file`""
        winget install $winget_args --id "$package_id" --override "$args"
        return
    } elseif ($results.Length -gt 1) {
        Write-Host "WARN Found multiple installed products for package '$package_id'"
    }
    
    $install_path = $results[0].installationPath
    & "$msvc_installer_dir\setup.exe" modify --installPath "$install_path" $msvc_installer_args --config "$config_file"
}

function Main {
    Install-Winget
    Install-Msvc "Microsoft.VisualStudio.2022.Community" "$env:USERPROFILE\scripts\msvc.vsconfig"
}

Main