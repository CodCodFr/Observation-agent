# --- Configuration ---
$DOCKER_IMAGE_NAME = "ghcr.io/codcodfr/observation-agent"
$IMAGE_TAG = "latest" # Or use a dynamic tag like "$(Get-Date -Format "yyyyMMdd-HHmmss")"

# --- 1. Load environment variables from .env file ---
Write-Host "Loading environment variables from .env file..."
$envFilePath = ".\.env"
if (Test-Path $envFilePath) {
    Get-Content $envFilePath | ForEach-Object {
        if ($_ -match "^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$") {
            $envName = $matches[1]
            $envValue = $matches[2]
            # Set for the current process, accessible by subsequent commands
            [System.Environment]::SetEnvironmentVariable($envName, $envValue, [System.EnvironmentVariableTarget]::Process)
            Write-Host "  - Loaded $envName"
        }
    }
} else {
    Write-Error "Error: .env file not found at $envFilePath"
    Exit 1
}

# --- 3. Ensure Docker Buildx is set up ---
Write-Host "Checking Docker Buildx setup..."
# Use existing builder or create new one
try {
    docker buildx use mybuilder || docker buildx create --use --name mybuilder --bootstrap
    Write-Host "Docker Buildx setup complete."
} catch {
    Write-Error "Failed to set up Docker Buildx. Make sure Docker Desktop is running."
    Exit 1
}

# --- 4. Login to GitHub Container Registry (GHCR) ---
Write-Host "Logging in to GHCR..."
# Assuming you have a GITHUB_USERNAME and GITHUB_PAT in your .env or environment
if (-not $env:GITHUB_USERNAME -or -not $env:GITHUB_PAT) {
    Write-Error "GITHUB_USERNAME or GITHUB_PAT environment variables are not set. Please set them in your .env file or system."
    Exit 1
}
try {
    echo $env:GITHUB_PAT | docker login ghcr.io -u $env:GITHUB_USERNAME --password-stdin
    Write-Host "Logged in to GHCR successfully."
} catch {
    Write-Error "GHCR login failed. Ensure GITHUB_USERNAME and GITHUB_PAT are correct and the PAT has 'write:packages' scope."
    Exit 1
}

# --- 5. Build and Push Multi-Architecture Docker Image ---
Write-Host "Building and pushing multi-architecture Docker image to ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}..."

# Define build arguments as a proper PowerShell array of strings
# Each --build-arg should be its own element in the array
$dockerBuildArgs = @(
    "--build-arg", "NPM_TOKEN=$env:NPM_TOKEN"
)
# Add other build args to this array if needed:
# $dockerBuildArgs += "--build-arg", "ANOTHER_ARG_NAME=value"

$platforms = "linux/amd64,linux/arm64/v8" # Target platforms

try {
    # Pass the array of arguments using @() to ensure they are treated as separate arguments
    docker buildx build --platform $platforms @dockerBuildArgs -t "${DOCKER_IMAGE_NAME}:${IMAGE_TAG}" --push .
    Write-Host "Multi-architecture Docker image pushed successfully to ${DOCKER_IMAGE_NAME}:${IMAGE_TAG}"
} catch {
    Write-Error "Docker buildx build and push failed. Check error messages above."
    Exit 1
}

Write-Host "Script finished."