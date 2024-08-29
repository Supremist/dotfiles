# This script will ensure installation of winget, git and nushell, prior to cloning dotfiles repo.
# Winget should be already installed on Windows 10 or newer. 
# But if OS is freshly installed, it may be required to trigger Microsoft Store update to get `winget` to be available as command.
# MSYS2 will be installed for git and other unix tools. 
# TODO: add Git For Windows as an option and skip MSYS2 installation.

# config
$env:GIT_WORK_TREE = $env:USERPROFILE # user home
$env:GIT_DIR = "$env:USERPROFILE\.dotfiles"
$repo = "Supremist/dotfiles"
$branch = "main"
$github_raw = "https://raw.githubusercontent.com"
$github = "https://github.com"

$MSYS_ROOT = "C:\msys64"
$nu = "C:\Program Files\nu\bin\nu.exe" # TODO
$sh = "$MSYS_ROOT\msys2_shell.cmd"
$sh_args = @("-no-start", "-defterm", "-here")
$winget_args = @("--silent", "--accept-package-agreements", "--accept-source-agreements", "--exact", "--scope", "machine")

$next_stage = "02-initial-checkout.nu"
$next_stage_file = "$env:TEMP\$next_stage"
$git_clone = @(
    "git clone --bare $github/$repo.git $env:GIT_DIR",
    "git show $branch:/scripts/install/$next_stage > $next_stage_file",
    "$nu $next_stage_file $branch",
    "$nu -e 'rm $next_stage_file'"
)

$Main = {
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
        Clear-Host # because sometimes parts of porgress bars remain visible and clutter visual space
        if (Get-Command winget -ErrorAction Ignore) { 
            Write-Host "Winget successfully installed."
        } else {
            Write-Error "Failed to install winget!"
            Pause
            return -1
        }
    }
    
    # TODO handle errors
    winget install $winget_args --id Nushell.Nushell

    if (Get-Command git -ErrorAction Ignore) {
        Write-Host "Found command: git"
        Write-Host "Cloning dotfiles using preinstalled git..."
        foreach ($cmd_line in $git_clone) {
            Invoke-Expression $cmd_line
        }
    } else {
        winget list --query --id MSYS2.MSYS2 | Out-Null
        if ($?) {
            Write-Host "MSYS2 already installed"
        } elseif (Test-Path $sh -PathType Leaf) {
            Write-Host "Found msys2 shell"
        } elseif (Test-Path $MSYS_ROOT) {
            Write-Error "MSYS2 Shell not found. Please remove '$MSYS_ROOT' dirctory to allow instalation"
            Pause
            return -1
        } else {
            winget install $winget_args --id MSYS2.MSYS2 --location "$MSYS_ROOT"
            if ($?) {
                Write-Host "MSYS2 successfully installed"
            } else {
                Write-Error "Failed to install MSYS2"
                Pause
                return -1
            }
        }
        Write-Host "Cloning dotfiles using MSYS2 shell..."
        foreach ($cmd_line in $git_clone) {
            & "$sh" $sh_args -msys -c $cmd_line
        }
    }
}

function Pause() {
    Write-Host -NoNewLine 'Press any key to continue...';
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}

& $Main