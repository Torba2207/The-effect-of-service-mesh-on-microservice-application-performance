param(
    [string]$Inventory = "$((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)/deployments/ansible/inventory.ini",
    [bool]$RunSetupKeys = $true
)

$ErrorActionPreference = "Stop"

if ($RunSetupKeys) {
    & "$PSScriptRoot/setup_keys.ps1"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
# Export REPO_ROOT to child processes (parity with Linux script)
$env:REPO_ROOT = $repoRoot

ansible-playbook "$repoRoot/deployments/ansible/setup_ai_vm.yml" -i $Inventory
ansible-playbook "$repoRoot/deployments/ansible/deploy_ai_vm.yml" -i $Inventory
ansible-playbook "$repoRoot/deployments/ansible/apply_baseline.yml" -i $Inventory

Write-Host "Initial environment setup complete."
