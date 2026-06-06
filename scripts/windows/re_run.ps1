param(
    [string]$Inventory = "$((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)/deployments/ansible/inventory.ini",
    [string]$Namespace = "thesis-test",
    [bool]$RunBuildPush = $false,
    [bool]$RunDeployAiVm = $true,
    [string]$GhcrOwner = "",
    [string]$Tag = "team-test"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

if ($RunBuildPush) {
    if ([string]::IsNullOrWhiteSpace($GhcrOwner)) {
        Write-Host "RunBuildPush=true requires -GhcrOwner."
        exit 1
    }
    & "$PSScriptRoot/build_and_push.ps1" -GhcrOwner $GhcrOwner -Tag $Tag
}

if ($RunDeployAiVm) {
    ansible-playbook "$repoRoot/deployments/ansible/deploy_ai_vm.yml" -i $Inventory
}

ansible-playbook "$repoRoot/deployments/ansible/reapply_deployments.yml" -i $Inventory

if (-not [string]::IsNullOrWhiteSpace($GhcrOwner)) {
    & "$PSScriptRoot/point_to_new.ps1" -GhcrOwner $GhcrOwner -Tag $Tag -Namespace $Namespace
}

kubectl get pods -n $Namespace
Write-Host "Re-run flow complete."
