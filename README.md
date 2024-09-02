## What's this?
My personal configs and install scripts. It meant to be checked out in home directory. No more doing tedious installs and configurations for the same software on every new system.

## Setup

### Windows
Automatic setup for freshly installed system (run from powershell):
```powershell
$u = "https://raw.githubusercontent.com/Supremist/dotfiles/main/scripts/install/01-bootstrap.ps1"; iex "& {$(iwr $u)} -Url $u"
```
> [!CAUTION]
> You should never run untrusted scripts from the internet. At least read the actual file before running it.

The [bootstrap](https://raw.githubusercontent.com/Supremist/dotfiles/main/scripts/install/01-bootstrap.ps1) script will install core software (only if not already in installed and in PATH):
 - Scoop
 - MinGit
 - Nushell

Then it will bare clone and checkout the repo into your home, while preserving backup of conflicted files. Repo url and branch is extracted from passed `Url` argument, so the whole script is fork-friendly.

TODO more installations...

### Linux
TODO
