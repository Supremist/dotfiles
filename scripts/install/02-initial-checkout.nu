# This script will checkout requested branch and deal with conflicted files in current working directory

def main [branch: string] {
    git config --local status.showUntrackedFiles no
    let checkout = git checkout $branch | complete
    if checkout.exit_code == 0 {
        print $"Successfully made initial checkout of '($branch)'"
        return 0
    }
    
    let conflicts = checkout.stderr | parse  --regex '^\s+(.*)' | get capture0 | str trim
    git checkout --orphan local_dotfiles
    $conflicts | each { |file| cp -f $file $"local_dotfiles_backup/($file)"; git add $file }
    git commit --author="checkout script <bot@example.com>" -m "Initial local dotfiles"
    
    checkout = git checkout $branch | complete
    if checkout.exit_code != 0 {
        print $checkout.stdout
        print $checkout.stderr
        error make { msg: $"Dotfiles checkout failed with exitcode ($checkout.exit_code)"}
    }
    print $"Successfuly made checkout of '($branch)'"
    print $"Your local dotfiles has conflicts with '($branch)'. Conflicted files are backuped in '($env.PWD)/local_dotfile_backup' dir AND in local branch 'local_dotfiles'"
    print "Please review them and run:"
    print "    git merge local_dotfiles"
    print "If commit contains any sensitive data, do not merge. Instead remove it:"
    print "    git branch -D local_dotfiles"
    print "    git reflog expire --expire=now --all"
    print "    git gc --prune=now --aggressive"
    print "You can also remove the repo and clone again."
}