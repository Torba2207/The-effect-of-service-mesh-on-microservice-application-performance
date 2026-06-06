param(
    [string]$GhcrOwner,
    [string]$Tag = "team-test",
    [string]$Namespace = "thesis-test",
    [string]$AiExternalManifest = "$((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)/deployments/k8s/ai-service/ai-service-external.yaml"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GhcrOwner)) {
    Write-Host "Usage: .\point_to_new.ps1 -GhcrOwner <github-username> [-Tag <tag>] [-Namespace <ns>]"
    exit 1
}

$registry = "ghcr.io/{0}" -f $GhcrOwner.ToLowerInvariant()

$services = @(
    "differential-equations-service",
    "fibonacci-service",
    "integration-service",
    "permutation-service",
    "digital-filters-service",
    "video-service"
)

Write-Host "Pointing deployments in namespace '$Namespace' to $registry:$Tag"

foreach ($service in $services) {
    kubectl set image "deployment/$service" "$service=$registry/$service:$Tag" -n $Namespace
}

kubectl apply -f $AiExternalManifest
kubectl set env deployment/permutation-service AI_SERVICE_BASEURL=http://ai-service/ -n $Namespace
kubectl rollout status deployment/permutation-service -n $Namespace --timeout=180s

Write-Host "Done."
