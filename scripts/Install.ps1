$ErrorActionPreference = "Stop"

. ~/scripts/lib/Elevate.ps1

Elevate-Shell $MyInvocation

$winget_args = @("--silent", "--accept-package-agreements", "--accept-source-agreements", "--exact")
$msvc_installer_dir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
$msvc_installer_args = @("--passive", "--norestart")

$MSYS_ROOT = "C:\msys64"
$MSYS_PKGS = "$MSYS_ROOT\opt\packages"
$sh = "$MSYS_ROOT\msys2_shell.cmd"
$sh_args = @("-no-start", "-defterm", "-here")

$config =  nu -c "open ~\scripts\install-packages.yaml | to json" | ConvertFrom-Json
$providers = $config.providers.PsObject.Properties.Name


function Install-Winget {
    param([switch] $AsJob)
    if (Get-Command winget -ErrorAction Ignore) {
        Write-Host "Found command: winget"
        return
    }
    $Job = {
        . ~/scripts/lib/MsStore.ps1
        Update-MsStoreApps @("Microsoft.WindowsStore_8wekyb3d8bbwe", "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe") # must contain winget
        if (Get-Command winget -ErrorAction Ignore) { 
            Write-Host "Winget successfully installed."
        } else {
            throw "Failed to install winget!"
        }
    }
    if ($AsJob) {
        return Start-Job $Job
    }
    & $Job
}

function Install-Scoop {
    param([String] $Location)
    
    if (Get-Command scoop -ErrorAction Ignore) {
        Write-Host "Found command: scoop"
        return
    }
    
    if (-not $Location) {
        if ($env:SCOOP) {
            $Location = $env:SCOOP
        } else {
            Write-Host "WARN env:SCOOP not found"
            $Location = "$env:SystemDrive\scoop"
        }
    }

    $is_admin = [Boolean] (Is-Admin)
    iex "& {$(irm get.scoop.sh)} -RunAsAdmin:`$$is_admin -ScoopDir '$Location'"

    # TODO remove scoop dir from user path, add it to system path
    # scoop bucket add main
    # scoop install aria2 # will speed up downloads
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
    
    if (Get-Command scoop -ErrorAction Ignore) {
        Write-Host "Installing vswhere via scoop..."
        scoop install vswhere
        return (Get-Command vswhere).Source
    } else {
        Write-Host "Installing vswhere via winget..."
        winget install $winget_args --id Microsoft.VisualStudio.Locator
        if (Test-Path $possible_location -PathType Leaf) {
            return $possible_location
        }
    }
    throw "Failed to find/install vswhere!"
}

function Install-Msvc {
    param(
        [String] $package_id,
        [String] $config_file
    )
    
    winget list --accept-source-agreements --exact --id $package_id | out-null
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
    $ret = @{}
    if ($results.Length -eq 0) {
        if ($installed_by_winget) {
            throw "Unable to find install location of '$package_id'"
        }

        Write-Host "Installing $package_id..."
        $ret.command = "winget" # run winget from root context to allow correct output of progress
        $ret.args = @("install") + $winget_args + @("--id", "$package_id", "--override", "$msvc_installer_args --config `"$config_file`"")
        return $ret
    } elseif ($results.Length -gt 1) {
        Write-Host "WARN Found multiple installed products for package '$package_id'"
    }
    
    $install_path = $results[0].installationPath
    Write-Host "Modifying installation of $package_id..."
    $ret.job = Start-Job { & "$using:msvc_installer_dir\setup.exe" modify --installPath "$using:install_path" $using:msvc_installer_args --config "$using:config_file"}
    return $ret
}

# Install packages, required for this script
function Install-PrioritizedSoft {
    if ($providers -contains "Microsoft.VisualStudio") {
        Get-VsWhere | Out-Null
    }
}

function Join-Job {
    param($job)
    if ($job) {
        Receive-Job -Job $job -Wait -AutoRemoveJob
    }
}

function Main {
    $need_winget = ($providers -contains "winget") -or ($providers -contains "msys2") -or ($providers -contains "Microsoft.VisualStudio")
    if ($need_winget) {
        $winget_job = Install-Winget -AsJob
    }
    if ($providers -contains "scoop") {
        Install-Scoop
    }
    
    Install-PrioritizedSoft # sequential
    
    if ($providers -contains "scoop") {
        $buckets = $config.providers.scoop
        $packages = $config.packages.scoop
        $packages_global = $config.packages."scoop.global"
        $scoop_job = Start-Job {
            foreach ($bucket in $using:buckets) {
                scoop bucket add "$bucket"
            }
            scoop install $using:packages
            scoop install -g $using:packages_global
        }
    }
    
    Join-Job $winget_job # ensure system have winget at this point

    if ($providers -contains "Microsoft.VisualStudio") {
        $msvc_list = $config.providers."Microsoft.VisualStudio"
        # To prevent multiple msvc installers from running
        # Install single msvc in parallel, and than install all remainig versions sequentially later
        if ($msvc_list.Count -ge 1) {
            $product = $msvc_list[0]
            $msvc_list = $msvc_list[1..$msvc_list.Count]
            $task = Install-Msvc "Microsoft.VisualStudio.$product" "$env:USERPROFILE\scripts\$product.vsconfig"
            if ($task.command) {
                & $task.command $task.args # allow correct progress output
            }
            $msvc_job = $task.job
        }
    }
    
    # Install Msys2
    if ($providers -contains "msys2") {
        if (Test-Path $sh -PathType Leaf) {
            Write-Host "Found command: msys2_shell"
        } else {
            winget install $winget_args --id MSYS2.MSYS2 --location "$MSYS_ROOT"
        }
        # Install msys2 packages as job
        #Start-Job -ScriptBlock { AddGitRepos; InstallMsys2Packages $input } -InputObject $config
        #Start-PshProcess -Cmd ./InstallMSYS2.ps1
    }
    
    if ($scoop_job) {
        Receive-Job -Job $scoop_job # show scoop progress to user
    }
    
    if ($providers -contains "node") {
        if (Get-Command node -ErrorAction Ignore) {
            Write-Host "Found command: node"
        } else {
            # installs fnm (Fast Node Manager)
            winget install $winget_args --id Schniz.fnm

            # Reload path
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

            # configure fnm environment
            fnm env --use-on-cd | Out-String | Invoke-Expression

            # download and install Node.js
            fnm use --install-if-missing 20
        }
        foreach ($package in $config.packages.node) {
            npm install -g "$package"
        }
    }

    # Install winget packages
    if ($providers -contains "winget")  {
        foreach ($package in $config.packages.winget) {
            winget install $winget_args --id $package
        }
    }
    
    if ($scoop_job) {
        Receive-Job -Job $scoop_job # show scoop progress to user
    }
    
    # Install remaining msvc
    if ($providers -contains "Microsoft.VisualStudio") {
        foreach($product in $msvc_list) {
            Join-Job $msvc_job
            $task = Install-Msvc "Microsoft.VisualStudio.$product" "$env:USERPROFILE\scripts\$product.vsconfig"
            if ($task.command) {
                & $task.command $task.args # allow correct progress output
            }
            $msvc_job = $task.job
        }
    }
    Join-Job $msvc_job
    Join-Job $scoop_job
}

Main