# This script will checkout requested branch and deal with conflicted files in current working directory

def main [branch: string] {
    use std
    git config --local status.showUntrackedFiles no
    let checkout = git checkout $branch | complete
    if $checkout.exit_code == 0 {
        print $"Successfully made initial checkout of '($branch)'"
        return 0
    }
    $env.GIT_COMMITTER_NAME = "checkout script"
    $env.GIT_COMMITTER_EMAIL = "<bot@example.com>"
    let conflicts = ($checkout.stderr | lines | parse  --regex '^\s+(.*)' | get capture0 | str trim)
    
    print "Conflicted files moved to '~/local_dotfiles_backup':"
    $conflicts | each { |file|
        print $"    ($file)"
        let backup = $"local_dotfiles_backup/($file)"
        mkdir ($backup | path dirname)
        mv -f $file $backup
    }
    print ""

    git checkout --orphan local_dotfiles
    git rm -rf . o> (std null-device)
    $conflicts | each { |file|
        let backup = $"local_dotfiles_backup/($file)"
        mkdir ($file | path dirname)
        cp -f $backup $file
        git add $file
    }
    git commit --author=$"($env.GIT_COMMITTER_NAME) <($env.GIT_COMMITTER_EMAIL)>" -m "Initial local dotfiles"
    
    let checkout = git checkout $branch | complete
    if $checkout.exit_code != 0 {
        print $checkout.stdout
        print $checkout.stderr
        error make { msg: $"Dotfiles checkout failed with exitcode ($checkout.exit_code)"}
    }
    print ""
    print $"Successfuly made checkout of '($branch)'"
    print $"Your local dotfiles has conflicts with '($branch)'. Conflicted files are backuped in '($env.PWD)/local_dotfile_backup' dir AND in local branch 'local_dotfiles'"
    print "Please review them and run:"
    print "    git merge --allow-unrelated-histories local_dotfiles"
    print "If commit contains any sensitive data, do not merge. Instead remove it:"
    print "    git branch -D local_dotfiles"
    print "    git reflog expire --expire=now --all"
    print "    git gc --prune=now --aggressive"
    print "You can also remove the repo and clone again."
}
