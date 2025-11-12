export-env {
    $env.VSINSTALLDIR = (vswhere -latest -format value -property installationPath) + (char psep)
}

export def --env vcvars [
    arch: string = 'amd64'
    --host_arch: string = 'amd64'
    platform?: string # {none} | store | uwp | onecore
    --winsdk: string
    --vc: string
    --spectre
    --debug: int = 0
] {
    let arch = ($arch | str downcase | if ($in == 'x64') { 'amd64' } else { $in } )
    let host_arch = ($host_arch | str downcase | if ($in == 'x64') { 'amd64' } else { $in } )
    let vcvars_bat = $'($env.VSINSTALLDIR)\VC\Auxiliary\Build\vcvarsall.bat'
    let get_env = $"($nu.home-path)/scripts/lib/GetEnv.ps1"
    let before = (tmp-name "before-env.XXX.json")
    let after = (tmp-name "after-env.XXX.json")
    mut tmp_env = {__GETENV: $'"($get_env)" "($after)"', VSCMD_SKIP_SENDTELEMETRY: 1}
    mut args = []
    if ($vcvars_bat | path exists) {
        $tmp_env = ($tmp_env | insert __VCVARS $'"($vcvars_bat)"')
        if ($arch == $host_arch) {
            $args = [$arch]
        } else {
            $args = [$"($host_arch)_($arch)"]
        }
        if ($platform | is-not-empty) {
            $args = ($args | append $platform)
        }
        if ($winsdk | is-not-empty) {
            $args = ($args | append $winsdk)
        }
        if ($vc | is-not-empty) {
            $args = ($args | append $"-vcvars_ver=($vc)")
        }
        if ($spectre) {
            $args = ($args | append "spectre")
        }
    } else {
        $tmp_env = ($tmp_env | insert __VCVARS $'"($env.VSINSTALLDIR)\Common7\Tools\VsDevCmd.bat"')
        $args = ($args | append $"-arch=($arch)" | append $"-host_arch=($host_arch)")
    }
    if ($debug > 0) {
        $tmp_env = ($tmp_env | insert VSCMD_DEBUG $debug | insert ERRORLEVEL $debug)
    }
    let args = ($args | str join ' ')
    with-env $tmp_env {
        ^powershell $get_env | from json | parse-env | to json | save -f $before
        print $"RUNNING: ($env.__VCVARS) ($args)"
        cmd.exe /C $"call %__VCVARS% ($args) & call powershell %__GETENV%"
    }
    open --raw $after  | from json | parse-env | to json | save -f $after
    let diff = (^jd -f=patch $before $after | from json)
    rm $before
    rm $after
    load-env-diff $diff
}