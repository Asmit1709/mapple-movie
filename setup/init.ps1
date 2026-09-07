# Helper script for Windows PowerShell to configure Kubernetes RBAC for github-action-user
$ErrorActionPreference = "Stop"

Write-Host "Fetching IAM github-action-user ARN..."
$userInfo = aws iam get-user --user-name github-action-user | ConvertFrom-Json
$userarn = $userInfo.User.Arn
Write-Host "Found User ARN: $userarn"

Write-Host "Downloading aws-iam-authenticator for Windows..."
$authenticatorUrl = "https://github.com/kubernetes-sigs/aws-iam-authenticator/releases/download/v0.6.2/aws-iam-authenticator_0.6.2_windows_amd64.exe"
Invoke-WebRequest -Uri $authenticatorUrl -OutFile "aws-iam-authenticator.exe"

try {
    Write-Host "Updating Kubernetes aws-auth permissions..."
    $kubeconfigPath = "$env:USERPROFILE\.kube\config"
    & .\aws-iam-authenticator.exe add user --userarn="$userarn" --username=github-action-role --groups=system:masters --kubeconfig="$kubeconfigPath" --prompt=false
    Write-Host "Successfully updated aws-auth ConfigMap for github-action-user!"
}
finally {
    Write-Host "Cleaning up temporary files..."
    if (Test-Path "aws-iam-authenticator.exe") {
        Remove-Item "aws-iam-authenticator.exe" -Force
    }
}

Write-Host "Done!"
