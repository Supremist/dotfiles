param (
    [string]$Output = "",  # Default to empty (stdout)
    [string]$Scope = "all"
)

# Function to get environment variables for a given scope
function Get-EnvVariables {
    param ([string]$envScope)
    switch ($envScope) {
        "process" { return [System.Environment]::GetEnvironmentVariables("Process") }
        "user"    { return [System.Environment]::GetEnvironmentVariables("User") }
        "machine" { return [System.Environment]::GetEnvironmentVariables("Machine") }
        "all"     { return [System.Environment]::GetEnvironmentVariables() }
        default {
            Write-Host "Invalid scope: $envScope. Use 'process', 'user', 'machine', or 'all'." -ForegroundColor Red
            exit 1
        }
    }
}

# Get the environment variables
$envData = Get-EnvVariables -envScope $Scope | ConvertTo-Json

# Output to file or stdout
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $False
if ($Output) {
    [System.IO.File]::WriteAllLines($Output, $envData, $OutputEncoding)
    Write-Host "Environment variables saved to: $Output"
} else {
    Write-Output $envData
}
