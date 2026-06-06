param(
    [string]$KeyDir = "$HOME/Documents/PG/Projects/.sshkeys",
    [string]$KeyName = "pgPB",
    [string]$SshUser = "root"
)

$ErrorActionPreference = "Stop"

$keyPath = Join-Path $KeyDir $KeyName
$hosts = @(
    "10.29.20.101",
    "10.29.20.102",
    "10.29.20.103",
    "10.29.20.111",
    "10.29.20.112",
    "10.29.20.113",
    "10.29.20.120",
    "10.29.20.130"
)

Write-Host "Creating key directory: $KeyDir"
New-Item -ItemType Directory -Path $KeyDir -Force | Out-Null

if (Test-Path $keyPath) {
    Write-Host "Existing key found: $keyPath"
}
else {
    Write-Host "Generating SSH key: $keyPath"
    ssh-keygen -t rsa -b 4096 -f $keyPath -N ""
}

foreach ($ip in $hosts) {
    Write-Host "Copying key to $SshUser@$ip (password prompt is expected)..."
    Get-Content "$keyPath.pub" | ssh "$SshUser@$ip" "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
}

Write-Host "Done."
