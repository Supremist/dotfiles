## What's this?
My personal configs and install scripts. It meant to be checked out in home directory. No more doing tedious installs and configurations for the same software on every new system.

## Setup

### Windows
Automatic setup from freshly installed system (run from powershell):
```powershell
start powershell -Verb RunAs -Args "-c iex (iwr https://raw.githubusercontent.com/Supremist/dotfiles/main/scripts/install/01-bootstrap.ps1)"
```
> [!CAUTION]
> You should never run untrusted scripts from the internet. Especially, you should not give them admin access.
> At least read the actual file before running it.

The [bootstrap](https://raw.githubusercontent.com/Supremist/dotfiles/main/scripts/install/01-bootstrap.ps1) script will install core software:
 - Winget (will trigger Microsoft Store update) 
 - Git (MinGit will be used, if not installed)
 - Nushell

Then it will bare clone and checkout this repo into your home, while preserving backup of conflicted files.

TODO more installations...

### Linux
TODO

