param(
    [string]$KeyDir = "",
    [string]$KeyName = "pgPB",
    [string]$SshUser = "root"
)

$ErrorActionPreference = "Stop"

# Compute repository root relative to script location
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
if ([string]::IsNullOrWhiteSpace($KeyDir)) { $KeyDir = Join-Path $repoRoot ".sshkeys" }

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
    # FIXED: Wrapped "" in single quotes so PowerShell passes it correctly
    ssh-keygen -t rsa -b 4096 -f $keyPath -N '""'
}

# Ensure .env at repo root contains SSH_PRIVATE_KEY pointing to generated key
$envFile = Join-Path $repoRoot ".env"
$kv = "SSH_PRIVATE_KEY=$keyPath"
if (Test-Path $envFile) {
    $content = Get-Content $envFile -Raw
    if ($content -match '(?m)^SSH_PRIVATE_KEY=') {
        $newContent = $content -replace '(?m)^SSH_PRIVATE_KEY=.*', $kv
        Set-Content -Path $envFile -Value $newContent -Force
    }
    else {
        Add-Content -Path $envFile -Value $kv
    }
}
else {
    Set-Content -Path $envFile -Value $kv -Force
}

foreach ($ip in $hosts) {
    Write-Host "Copying key to $SshUser@$ip (password prompt is expected)..."
    Get-Content "$keyPath.pub" | ssh "$SshUser@$ip" "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && cat >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
}

Write-Host "Done."