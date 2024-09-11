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

export def find_free_name [
    is_free?: closure
] {
    let path = $in
    print $path
    let path = if ($path | describe) == string {
        $path | path parse
    } else {
        $path
    }
    let is_free = if $is_free == null { 
        {|new_path| not ($new_path | path join | path exists) }
    } else { 
        $is_free
    }
    if (do $is_free $path) {
        return $path
    }
    let match = $path.stem | parse -r '^(?<name>.+)_(?<i>\d+)$' | get -i 0
    mut i = if $match == null { 2 } else { ($match.i | into int) + 1 }
    let stem = if $match == null { $path.stem } else { $match.name }
    loop {
        let new_stem = $"($stem)_($i)"
        let new_path = $path | update stem { $new_stem }
        if (do $is_free $new_path) {
            return $new_path
        }
        $i = $i + 1
    }
}

export def name_collisions [
    src_root: string # absolute
    src_path: string # absolute
    dest_root: string # absolute
] {
    let src_rel = try { $src_path | path relative-to $src_root }
    if $src_rel == null {
        return [$src_path]
    }
    let src_files = if ($src_path | path type) == dir { 
        ls -fa ($"($src_path)/**/*" | into glob) | where type == file | get name
    } else { 
        [$src_path]
    }
    return ($src_files | filter {|src| $dest_root | path join ($src | path relative-to $src_root) | path exists })
}


# Copy $path/$file to $backup_dir/$tag/$file
# Can accept relative path as $file
# If $file is not specified, consider $path relative to CWD
# If $tag already exists - try to merge. If has name collision - rename to $tag_2 and so on...
export def backup [
    tag: string
    path: string
    file?: string
] {
    let backup_dir = $"($nu.home-path)/backup"
    let cfg_path = $backup_dir | path join "root_dirs.json"
    let cfg = try { $cfg_path | open } catch { {} }
    let root = if $file == null { pwd } else { $path } | path expand -n
    let path = if $file == null { $path } else { $path | path join $file } | path expand -n
    let tag_dir = $backup_dir | path join $tag | find_free_name {|dest|
        let dest_str = $dest | path join
        if ($dest_str | path exists) {
            let stored_root = $cfg | get -i $dest.stem
            if $stored_root == null { return false }
            let collisions = name_collisions $stored_root $path $dest_str
            #print $"Collisions: ($collisions)"
            return ($collisions | is-empty)
        }
        return true
    }
    let tag_changed = ($tag != $tag_dir.stem)
    let tag = $tag_dir.stem
    let tag_dir = $tag_dir | path join
    
    if ($tag_dir | path exists) {
        let root = $cfg | get $tag
    } else {
        mkdir $tag_dir
        $cfg | upsert $tag { $root } | save -f $cfg_path
    }
    let rel_path = $path | path relative-to $root
    let dest = $tag_dir | path join $rel_path
    #print $"Backing up '($path)' into '($tag)'..."
    mkdir ($dest | path dirname)
    cp -rf $path $dest
    return {src: $path, tag: $tag, dest: $dest, root: $root}
}