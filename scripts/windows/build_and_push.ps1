param(
    [string]$GhcrOwner,
    [string]$Tag = "team-test",
    [string]$BaseDir = "$((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)/ServiceMeshTestApplication"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GhcrOwner)) {
    Write-Host "Usage: .\build_and_push.ps1 -GhcrOwner <github-username> [-Tag <tag>]"
    exit 1
}

$registry = "ghcr.io/{0}" -f $GhcrOwner.ToLowerInvariant()

$services = @(
    @{ Dir = "DifferentialEquationsService"; Image = "differential-equations-service" },
    @{ Dir = "FibonacciService";             Image = "fibonacci-service" },
    @{ Dir = "IntegrationService";           Image = "integration-service" },
    @{ Dir = "PermutationService";           Image = "permutation-service" },
    @{ Dir = "DigitalFiltersService";        Image = "digital-filters-service" },
    @{ Dir = "VideoService";                 Image = "video-service" }
)

Write-Host "Building and pushing images to $registry with tag $Tag"

foreach ($service in $services) {
    $dockerfile = Join-Path (Join-Path $BaseDir $service.Dir) "Dockerfile"
    $imageRef = "$registry/$($service.Image):$Tag"

    if (-not (Test-Path $dockerfile)) {
        Write-Host "Skipping $($service.Image) (missing Dockerfile: $dockerfile)"
        continue
    }

    Write-Host "Building $imageRef"
    docker build -t $imageRef -f $dockerfile $BaseDir
    docker push $imageRef
}

Write-Host "Done."
