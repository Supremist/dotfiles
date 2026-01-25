# New api
#
# backup mkdir tag root_dir
# backup clean-tags --remove-empty-folders
# backup versions 
# [file1, file2] | backup save tag --root="dir" --force(-f)
# [file1, file2] | backup restore tag? --move(-m)

# I want a simple api like
# backup [--tag(t) tag] file1 file2...
# trash  [--tag(t) tag] file1 file2...
# restore file

# what if file is already have a backup?
# - existent beckups should not be removed/overwritten
# - new unique part should be added to file name
# - new path should be returned from backup function



alias _save = save

let backup_dir = $"($nu.home-path)/backup"
let default_tag = "quicksave"

# Copy $path/$file to $backup_dir/$tag/$file
# Can accept relative path as $file
# If $file is not specified, consider $path relative to CWD
# If $tag already exists - try to merge. If has name collision - rename to $tag_2 and so on...
# --force, -f: overwrite existing backups
export def save [
    tag: string
    path: string
    file?: string
    #--root(-r): string
    --force(-f)
] {
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
                let stored_root = $cfg | get -o $dest.stem
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
        $cfg | upsert $tag { $root } | _save -f $cfg_path
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
export def versions [
    path: string
] {
    let backup_dir = $"($nu.home-path)/backup" # TODO move to config
    let path = $path | path expand -n
    let cfg_path = $backup_dir | path join "root_dirs.json"
    let cfg = try { $cfg_path | open } catch { {} }
    let cfg = $cfg | transpose tag root | where {|x| $backup_dir | path join $x.tag | path exists }
    $cfg | transpose -rid | _save -f $cfg_path
    let cfg = $cfg | each {|x| try {
        let target = [$backup_dir, $x.tag, ($path | path relative-to $x.root)] | path join
        ls -lafD $target | get 0 | insert tag { $x.tag }
    }} | sort-by --reverse created
    return $cfg
}

export def restore [
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