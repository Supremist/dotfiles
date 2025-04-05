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

# Usage:
# capture-env-diff {|get_env, env_file| C:\msys64\msys2_shell.cmd "-here" "-full-path" "-ucrt64" "-no-start" "-defterm" "-c" $"powershell \"($get_env)\" -Output \"($env_file)\"" } -f patch
export def capture-env-diff [
    script: closure
    --format (-f): string = "jd"
] {
    let script_contents = $in
    let env_file = (mktemp -t env.XXX.json)
    let get_env_script = $"($nu.home-path)/scripts/lib/GetEnv.ps1"
    $script_contents | do $script $get_env_script $env_file
    env-diff $env_file --format $format
}

export def env-diff [
    env_file: string
    --format (-f): string = "jd"
] {
    let get_env_script = $"($nu.home-path)/scripts/lib/GetEnv.ps1"
    let old_env_file = (^powershell $get_env_script | from json | parse-env | to json | save-tmp old-env.XXX.json)
    let after_env = (open --raw $env_file | from json | parse-env)
    let result = match $format {
        "jd" => ($after_env | to json | jdc  $old_env_file)
        "patch" => ($after_env | to json | jd -f=patch $old_env_file | from json)
    }
    rm $old_env_file
    $result
}

export def collect-files [
    paths: list<string>
    exts: list<string> = []
] {
    mut files = ([])
    let exts = ($exts | str downcase)
    for path in $paths {
        if (not ($path | path exists)) {
            print $"Does not exists: ($path)"
            continue
        }
        let matched_files = (ls -fa $path | where type == "file" | each { |file|
            let parsed = ($file.name | path parse | update extension { str downcase })
            if ($parsed.extension in $exts) or ($exts | is-empty) {
                $file | merge $parsed | update stem { str downcase }
            }
        })
        $files = ($files ++ $matched_files)
    }
    $files
}

def filter-shadowed-paths [] {
    mut result = ($in | str downcase)
    let shadowing_allowed = ([
        ['C:\Windows\System32', 'C:\Windows'],
        ['C:\msys64\ucrt64\bin', 'C:\msys64\usr\bin']
    ] | each {$in | str downcase})
    for shadows in $shadowing_allowed {
        if $shadows.0 in $result {
            $result = ($result | filter { $in not-in ($shadows | skip 1)})
        }
    }
    return $result
}


export def path-conflicts [
    exts: list<string> = []
] {
    #let exts = ['dll', 'so', '', 'rll', 'cpl', 'lua', 'drv', 'ocx', 'efi', 'ps1', 'psd1', 'psm1', 'def', 'lib']
    let win_path = (['C:\Windows', 'C:\Windows\System32', 'C:\Users\sergk\AppData\Local\Microsoft\WindowsApps'] | str downcase)
    let files = (collect-files $env.PATH $exts)
    let conflicts = ($files | group-by --to-table stem | get items | filter { ($in.parent | filter-shadowed-paths | uniq | length) > 1})
    $conflicts
}

export def tmp-name [
    template?: string
    --rand (-r): string = 'X'
] {
    $env.TEMP + (char psep) + if ($template | is-empty) {
        "tmp-" + (random chars -l 6)
    } else if ($rand | is-empty) {
        $template
    } else {
        $template | split row '' | each {|char|
            if $char == $rand {
                (random chars -l 1)
            } else {
                $char
            }
        } | str join ''
    }
}

export def save-tmp [
    template?: string
    --rand (-r): string = 'X'
] {
    let content = $in
    let file_path = tmp-name $template --rand $rand
    $in | save -f $file_path
    $file_path
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
# --force, -f: overwrite existing backups
export def "backup save" [
    tag: string
    path: string
    file?: string
    --force(-f)
] {
    let backup_dir = $"($nu.home-path)/backup"
    let cfg_path = $backup_dir | path join "root_dirs.json"
    let cfg = try { $cfg_path | open } catch { {} }
    let root = if $file == null { pwd } else { $path } | path expand -n
    let path = if $file == null { $path } else { $path | path join $file } | path expand -n
    let tag_dir = ($backup_dir | path join $tag | path parse)
    let tag_dir = if $force {
        $tag_dir
    } else {
        $tag_dir | find_free_name {|dest|
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
    }
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
    cp -r --force=$force --no-clobber=(not $force) $path $dest
    return {src: $path, tag: $tag, dest: $dest, root: $root}
}


# Get backuped versions of $path
# Possible usage:
# backup versions file | get 0 | do { rm $in.name } # remove most recent backup
# backup versions file | each { rm $in.name } # remove all backups of file
export def "backup versions" [
    path: string
] {
    let backup_dir = $"($nu.home-path)/backup" # TODO move to config
    let path = $path | path expand -n
    let cfg_path = $backup_dir | path join "root_dirs.json"
    let cfg = try { $cfg_path | open } catch { {} }
    let cfg = $cfg | transpose tag root | filter {|x| $backup_dir | path join $x.tag | path exists }
    $cfg | transpose -rid | save -f $cfg_path
    let cfg = $cfg | each {|x| try {
        let target = [$backup_dir, $x.tag, ($path | path relative-to $x.root)] | path join
        ls -lafD $target | get 0 | insert tag { $x.tag }
    }} | sort-by --reverse created
    return $cfg
}

export def "backup restore" [
    path: string # target file path or path to backuped file
    # dest?: string # TODO allow custom destination
    --recent(-r) # restore the most recent versions when multiple verions found
] {
    let backup_dir = $"($nu.home-path)/backup" # TODO move to config
    let path = $path | path expand -n # TODO allow path relative to backup_dir
    let cfg_path = $backup_dir | path join "root_dirs.json"
    let cfg = try { $cfg_path | open } catch { {} }
    let rel_path = try { $path | path relative-to $backup_dir }
    let result = if $rel_path == null {
        let versions = backup versions $path
        let version  = match [($versions | length), $recent] {
            [0, _] => { error make {msg: $"No backups found for '($path)'."} },
            [1, _] | [_, true] => { $versions | get 0 },
            _ => { error make {msg: $"Found multiple backups for '($path)'. Add --recent flag, or review 'backup versions'"} }
        }
        { file: $path, backup: $version.name, tag: $version.tag }
    } else {
        let rel_path = $rel_path | path split
        let tag = $rel_path | first
        let rel_path = $rel_path | skip 1 | path join
        let file = $cfg | get $tag | path join $rel_path
        { file: $file, backup: $path, tag: $tag }
    }
    mkdir ($result.file | path dirname)
    cp -rf $result.backup $result.file
    return $result
}

alias bkup = backup save

def --wrapped jd [
    --inverted (-i)
    --color (-c)
    to
    ...argv
] {
    let from = $in
    let file_name = (tmp-name obj.XXX.json)
    let input = if $inverted {
        $from | to json | save -f $file_name
        $to | to json
    } else {
        $to | to json | save -f $file_name
        $from | to json
    }
    let out = if $color {
        $input | ^jd -f jd -color ...$argv  $file_name | lines | each { |line|
            let stripped = $line | ansi strip
            if ($stripped | str starts-with '@ ') {
                $'(ansi purple)($stripped)(ansi reset)'
            } else {
                $line
            }
        } | to text
    } else {
        $input | ^jd -f patch ...$argv $file_name | from json
    }
    rm $file_name
    $out
}

def --wrapped jdc [...argv] {
    ^jd -f jd -color ...$argv | lines | each { |line|
        let stripped = $line | ansi strip
        if ($stripped | str starts-with '@ ') {
            $'(ansi purple)($stripped)(ansi reset)'
        } else {
            $line
        }
    } | to text
}

def --wrapped fsutil [cmd, subcmd, ...argv] {
    let cmd = ($cmd | str downcase)
    let subcmd = ($subcmd | str downcase)
    match [$cmd, $subcmd] {
        ['reparsepoint', 'query'] => {
            let output = (^fsutil $cmd $subcmd ...$argv | lines | filter {$in | is-not-empty} | split list -r '(Data:)|(Reparse Data:)')
            let result = $output.0 | split column ':' | str trim | transpose -rid
            let data = ($output.1 | each { $in | str substring 7..54 } | str join '' | str replace -a ' ' '' | decode hex)
            let decoded = ($data | bytes at 4.. | bytes replace -a 0x[0000] 0x[000a] | decode utf-16 | lines)
            $result | insert Data $data | insert Decoded $decoded
        }
        _ => {
            ^fsutil $cmd $subcmd ...$argv
        }
    }
}

def --wrapped scoop [...argv] {
    let args = ($argv | each { $"\"($in)\"" } | str join ' ')
    ^powershell -c $"scoop ($args)"
}

def check-proc [] {
    let result = $in
    let span = (metadata $in).span
    if ($result.stderr | is-not-empty) or ($result.exit_code != 0) {
        print $result.stdout
        error make {
            msg: $"Exit code: ($result.exit_code)\n($result.stderr)",
            label: {
                text: "from this external process",
                span: $span
            }
        }
    } else {
        return $result.stdout
    }
}

def reg [
    command: string
    key? : string
    --expand (-e)
] {
    let values = $in
    let flags = if $expand { '-Expand' } else {''}
    if ($key | is-empty) {
        if $command == 'set' {
            error make {msg: "Argument 'key' should be specified for 'set' command"}
        }
        # take key from input
        ^powershell $'($nu.home-path)/scripts/lib/Reg.ps1 "($command)" "($values)" ($flags)' | complete | check-proc
    } else {
        $values | to json | ^powershell $'($nu.home-path)/scripts/lib/Reg.ps1 "($command)" "($key)" ($flags)' | complete | check-proc
    } | from json
}