export-env {
    $env.GIT_DIR = $"($nu.home-path)\\.dotfiles"
    $env.GIT_WORK_TREE = $nu.home-path
}

export alias gitdf = git $"--git-dir=($nu.home-path)\\.dotfiles" $"--work-tree=($nu.home-path)"

export def --env dotfiles-deactivate [] {
    hide-env GIT_DIR
    hide-env GIT_WORK_TREE
}