# This script will ensure installation of winget, git and nushell, prior to cloning dotfiles repo.
# Winget should be already installed on Windows 10 or newer. 
# But if OS is freshly installed, it may be required to trigger Microsoft Store update to get `winget` to be available as command.
# MinGit will be installed, if git is not found.

# Get-WmiObject -Class Win32_Product -Filter 'Name like "%Microsoft Office%"' | Select Caption,InstallLocation
# wmic product where "Name='Exact name of your app'" get InstallLocation

# config
$env:GIT_WORK_TREE = $env:USERPROFILE # user home
$env:GIT_DIR = "$env:USERPROFILE\.dotfiles"
$repo = "Supremist/dotfiles"
$branch = "main"
$github_raw = "https://raw.githubusercontent.com"
$github = "https://github.com"

$winget_args = @("--silent", "--accept-package-agreements", "--accept-source-agreements", "--exact") # "--scope", "machine"

function Main() {
    if (Test-Path $env:GIT_DIR) {
        Write-Host "Dotfiles dir already exists"
        Pause
        return 0
    }
    cd $env:USERPROFILE

    if (Get-Command winget -ErrorAction Ignore) {
        Write-Host "Found command: winget"
    } else {
        Write-Host "Command not found: winget"
        Write-Host "Loading MsStore update script..."
        Invoke-Expression (Invoke-WebRequest "$github_raw/$repo/$branch/scripts/lib/MsStore.ps1")
        Update-MsStoreApps @("Microsoft.WindowsStore_8wekyb3d8bbwe", "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe") # must contain winget
        if (Get-Command winget -ErrorAction Ignore) { 
            Write-Host "Winget successfully installed."
        } else {
            Write-Error "Failed to install winget!"
            Pause
            return -1
        }
    }

    # TODO handle errors
    # TODO remove --override after https://github.com/nushell/nushell/issues/13719
    winget install $winget_args --id "Nushell.Nushell" --override "ALLUSERS=1"

    if (Get-Command git -ErrorAction Ignore) {
        Write-Host "Found command: git"
        Write-Host "Cloning dotfiles using preinstalled git..."
    } else {
        winget install $winget_args --location "$env:USERPROFILE\MinGit" --id Git.MinGit
        if ($?) {
            Write-Host "MinGit successfully installed into '$env:USERPROFILE\MinGit'. Reinstall full version later."
        } else {
            Write-Error "Failed to install MinGit!"
            Pause
            return -1
        }
    }
    
    # Reload path
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $next_stage = "02-initial-checkout.nu"
    $next_stage_file = "$env:TEMP\$next_stage"
    $utf8_no_bom = New-Object System.Text.UTF8Encoding $False
    
    git clone --bare "$github/$repo.git" "$env:GIT_DIR"
    $stage_data = git show "${branch}:scripts/install/$next_stage"
    [System.IO.File]::WriteAllLines($next_stage_file, $stage_data, $utf8_no_bom)
    nu "$next_stage_file" "$branch"
    nu -e "rm $next_stage_file"
}

function Pause() {
    Write-Host -NoNewLine 'Press any key to continue...';
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}

Main