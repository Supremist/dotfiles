#export def ps-table [] { # better to use detect columns https://www.nushell.sh/cookbook/parsing.html
#    let $ps_lines = $in | lines
#    let $names = $ps_lines | first | split row ' ' | filter { $in | is-not-empty} | str downcase
#    return ($ps_lines | skip 1 | split column --collapse-empty ' ' ...$names)
#}

# $"($env.TEMP)\\ssh-*\\agent.18780" | into glob | ls $in
# ^ps | ps-table | where {$in.command | str ends-with /ssh-agent} | get 0.pid
# ps | where name == 'ssh-agent' or name == 'ssh-agent.exe' | get 0.pid

export def start-ssh [] {
    let agent_procs = ^ps | detect columns | join -r (ps) WINPID pid | where name =~ 'ssh-agent(\.exe)?' 
    let agent_pids = $agent_procs | select PID pid | values | flatten | filter {$in | is-not-empty} | uniq
    let temps = [$env.TEMP, $env.TMP, (cygpath -w /tmp)] | uniq 
    print $agent_pids
    for pid in $agent_pids {
        let locations = $temps | each { $"($in)\\ssh-*\\agent.($pid)" | into glob } | flatten
        print $locations
        let socks = try { ls ...$locations }
        if ($socks | is-empty) { continue }
        if ($socks | length) > 1 {
            print $"Found multiple sockets for pid ($pid): ($socks | get name)"
            print "Choosing first socket"    
        }
        return {
            SSH_AUTH_SOCK: ($socks | first | get name)
            SSH_AGENT_PID: ($pid)
        }
    }
    print "Starting new ssh-agent..."
    #return (^ssh-agent | capture-win-env script 'C:\msys64\msys2_shell.cmd' "-here" "-ucrt64" "-no-start" "-defterm") # TODO bash
}

export def capture-win-env [
        mode: string
        shell: string
        ...args: string
] {
    let script_contents = $in | split row "\n" | split row ';' | str trim | filter {$in | is-not-empty } | str join '; ';
    let start_env = '<ENV_CAPTURE_START_MARKER>'
    let end_env = '<ENV_CAPTURE_END_MARKER>'
    let env_var_blacklist = ["SHLVL", "_", "_AST_FEATURES"]
    let ps_get_env_code = [
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()", 
        $"Write-Output '($start_env)'", 
        "[System.Environment]::GetEnvironmentVariables() | ConvertTo-Json",
        $"Write-Output '($end_env)'", 
    ] | str join '; '
    let ps_get_env = if shell == 'powershell' { $ps_get_env_code } else { $"powershell -c \"($ps_get_env_code)\"" }
    let before = if $mode == 'full' { (^powershell -c $ps_get_env_code) }
    let script = [$script_contents, $ps_get_env] | if $mode == 'script' { prepend $ps_get_env } else { $in } | str join "; "
    #print $shell ...$args "-c" $script
    let out = [$before, (^$shell ...$args -c $script)] | str join ''
    | split row $start_env 
    | split row $end_env
    | {
        before: ($in | get 1 | from json)
        after: ($in | get 3 | from json)
        stdout: ($in | select 0 2 4 | str join "" | str trim)
    }
    print $out.stdout
    return ($out.after 
    | transpose key value 
    | filter {|$i| ($out.before | get -i $i.key) != $i.value and $i.key not-in $env_var_blacklist}
    | transpose --header-row --as-record)
}

def --env dotfiles-activate [] {
    $env.GIT_DIR = $"($nu.home-path)\\.dotfiles"
    $env.GIT_WORK_TREE = $nu.home-path
    cd $nu.home-path
}

def --env dotfiles-deactivate [] {
    hide-env GIT_DIR
    hide-env GIT_WORK_TREE
}

alias gitdf = git $"--git-dir=($nu.home-path)\\.dotfiles" $"--work-tree=($nu.home-path)"