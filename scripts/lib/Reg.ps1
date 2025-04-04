# reg create key
# reg remove key
# reg get key
# reg set key values
# reg ls key // get subkeys

param (
    [string]$Command,
    [string]$Key
)

$ErrorActionPreference = "Stop"

function Check-RegistryKey {
    param ([string]$Key)
    if ((Split-Path $Key -Qualifier | Get-Item).GetType().Name -ne 'RegistryKey') {
        throw "Invalid registry key $Key"
    }
}

function Create-Key {
    param ([string]$Key)
    Check-RegistryKey $Key
    New-Item -Path $Key -Force | Out-Null
}

function Remove-Key {
    param ([string]$Key)
    Check-RegistryKey $Key
    Remove-Item -Path $Key -Force -Recurse:$true -Confirm:$false
}

function Get-Values {
    param ([string]$Key)
    $regKey = Get-Item -Path $Key
    $result = @()
    foreach ($name in $regKey.GetValueNames()) {
        $result += @{"name" = $name; "kind" = $regKey.GetValueKind($name).ToString(); "value" = $regKey.GetValue($name) }
    }
    $regKey.Close()
    $result | ConvertTo-Json
}

function Set-Values {
    param ([string]$Key, [string]$JsonValues)
    Check-RegistryKey $Key
    $regKey = Get-Item -Path $Key -ErrorAction "Ignore"
    if (-not $regKey) {
        Create-Key -Key $Key
        $regKey = Get-Item -Path $Key
    }
    $regKey = $regKey.OpenSubKey("", "ReadWriteSubTree")
    $values = $JsonValues | ConvertFrom-Json
    foreach ($obj in $values) {
        if ($obj.value -eq $null) {
            $regKey.DeleteValue($obj.name, $false)
        } else {
            $regKey.SetValue($obj.name, $obj.value, $obj.kind)
        }
    }
    $regKey.Close()
}

function List-Subkeys {
    param ([string]$Key)
    $regKey = Get-Item -Path $Key
    if (-not $regKey) {
        throw "Registry Key doesn't exist: $Key"
    }
    $regKey.GetSubKeyNames() | ConvertTo-Json
    $regKey.Close()
}

switch ($Command.ToLower()) {
    "create" { Create-Key -Key $Key }
    {($_ -eq "rm") -or ($_ -eq "remove")} { Remove-Key -Key $Key }
    "get" { Get-Values -Key $Key }
    "set" { Set-Values -Key $Key -JsonValues ([Console]::In.ReadToEnd()) }
    {($_ -eq "ls") -or ($_ -eq "list")} { List-Subkeys -Key $Key }
    default { Write-Error "Unknown command: $Command" }
}
