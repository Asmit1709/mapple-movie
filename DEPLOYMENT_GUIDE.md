# Movie Picture CI/CD Pipeline - Deployment & Verification Guide

This guide provides step-by-step instructions for running, testing, and verifying the GitHub Actions CI/CD pipelines for the **Movie Picture** application.

---

## Architecture Overview

The system consists of two microservices:
1. **Frontend**: React application written in TypeScript/JavaScript (`starter/frontend`).
2. **Backend**: REST API written in Python Flask (`starter/backend`).

Four GitHub Actions workflows are provided under `.github/workflows/`:
- **`frontend-ci.yml`**: Triggered on Pull Requests modifying `starter/frontend/**` or manual dispatch. Executes parallel `lint` and `test` jobs, followed by a Docker `build` job utilizing build-arg `REACT_APP_MOVIE_API_URL`.
- **`frontend-cd.yml`**: Triggered on Push to `main` modifying `starter/frontend/**` or manual dispatch. Runs lint/test, builds and tags the Docker image with Git SHA (`${{ github.sha }}`), pushes to Amazon ECR, and deploys to Amazon EKS via `kustomize`.
- **`backend-ci.yml`**: Triggered on Pull Requests modifying `starter/backend/**` or manual dispatch. Executes parallel `lint` (`flake8`) and `test` (`pytest` via `pipenv`), followed by a Docker `build` job.
- **`backend-cd.yml`**: Triggered on Push to `main` modifying `starter/backend/**` or manual dispatch. Runs lint/test, builds and tags the Docker image with Git SHA, pushes to Amazon ECR, and deploys to Amazon EKS via `kustomize`.

---

## Step 1: Git Repository Setup & Push to GitHub

1. Create a **new public GitHub repository** (e.g., `cd12354-Movie-Picture-Pipeline` or `movie-picture-pipeline`).
   > *Note: Public repositories receive free GitHub Actions compute minutes.*

2. Initialize / update git remote and push your code:
   ```bash
   git add .
   git commit -m "feat: implement GitHub Actions CI/CD pipelines for frontend and backend"
   git branch -M main
   git remote set-url origin https://github.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>.git
   git push -u origin main
   ```

---

## Step 2: Provision AWS Infrastructure (Terraform)

1. Navigate to the terraform directory:
   ```bash
   cd setup/terraform
   ```

2. Export your AWS credentials (or ensure AWS CLI is configured):
   ```bash
   export AWS_ACCESS_KEY_ID="<YOUR_AWS_ACCESS_KEY_ID>"
   export AWS_SECRET_ACCESS_KEY="<YOUR_AWS_SECRET_ACCESS_KEY>"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

3. Initialize and apply the Terraform configuration:
   ```bash
   terraform init
   terraform apply -auto-approve
   ```

4. Retrieve outputs:
   ```bash
   terraform output
   ```
   *Expected outputs include: `frontend_ecr`, `backend_ecr`, `cluster_name` (`cluster`), and `github_action_user_arn`.*

---

## Step 3: Configure AWS IAM & Kubernetes Access

1. Generate Access Keys for `github-action-user`:
   - Go to AWS Management Console -> **IAM** -> **Users**.
   - Select `github-action-user`.
   - Under **Security credentials**, click **Create access key** -> Choose **Application running outside AWS** -> Save the Access Key and Secret Key.

2. Update your local kubeconfig to interact with the EKS cluster:
   ```bash
   aws eks update-kubeconfig --name cluster --region us-east-1
   ```

3. Authorize the GitHub Action user in Kubernetes:
   ```bash
   cd setup
   chmod +x init.sh
   ./init.sh
   ```
   *This adds `github-action-user` to the Kubernetes `aws-auth` ConfigMap under `system:masters`.*

---

## Step 4: Configure GitHub Secrets

In your GitHub repository:
1. Navigate to **Settings** -> **Secrets and variables** -> **Actions**.
2. Click **New repository secret** and add:
   - `AWS_ACCESS_KEY_ID`: Access key generated for `github-action-user`.
   - `AWS_SECRET_ACCESS_KEY`: Secret key generated for `github-action-user`.
   - `AWS_REGION`: `us-east-1` (optional; defaults to `us-east-1` in workflow).

---

## Step 5: Verifying Continuous Integration (CI)

### 1. Happy Path Testing (Pull Request)
1. Create and switch to a feature branch:
   ```bash
   git checkout -b feature/test-ci
   ```
2. Make a minor comment change in `starter/frontend/src/App.js` or `starter/backend/movies/resources.py`.
3. Commit and push:
   ```bash
   git commit -am "test: trigger CI pipeline"
   git push -u origin feature/test-ci
   ```
4. Open a Pull Request against `main`.
5. Observe GitHub Actions:
   - For frontend changes: `Frontend CI` runs `lint` and `test` in parallel. Once both succeed, `build` runs and constructs the Docker image.
   - For backend changes: `Backend CI` runs `lint` and `test` in parallel. Once both succeed, `build` runs and builds the Docker image.

### 2. Failure Path Testing (Negative Scenarios)
Verify that the CI pipelines properly catch and fail on errors:

- **Frontend Lint Failure**:
  Temporarily modify `starter/frontend/.eslintrc.js` to set `process.env.FAIL_LINT ? 2 : 0` or introduce an unformatted line or syntax violation. Push on branch to verify the `lint` job fails and blocks `build`.
- **Frontend Test Failure**:
  Set `FAIL_TEST=true` in test configuration or change the expected heading text in `starter/frontend/src/components/__tests__/App.test.js`. Push to verify `test` fails and blocks `build`.
- **Backend Lint Failure**:
  Run `pipenv run lint-fail` or introduce a line exceeding 120 chars. Push to verify `lint` fails and blocks `build`.
- **Backend Test Failure**:
  Set `FAIL_TEST=true` in `starter/backend/test_app.py`. Push to verify `test` fails and blocks `build`.

---

## Step 6: Verifying Continuous Deployment (CD)

1. Merge your Pull Request into `main` (or push directly to `main`):
   ```bash
   git checkout main
   git merge feature/test-ci
   git push origin main
   ```
2. Or trigger manually via GitHub Actions tab:
   - Select **Frontend CD** or **Backend CD** -> Click **Run workflow** on `main`.
3. Verify Execution:
   - `lint` and `test` execute in parallel.
   - `build` logs into Amazon ECR, tags image with `${{ github.sha }}` and pushes to ECR.
   - `deploy` configures kubeconfig, runs `kustomize edit set image ...`, applies manifests via `kubectl apply -f -`, and checks rollout status with `kubectl rollout status`.

---

## Step 7: Verifying Application in Kubernetes

Check the running pods and services in your Kubernetes cluster:

```bash
# Check pod status
kubectl get pods -n default

# Check deployment rollout
kubectl get deployments -n default

# Check services
kubectl get svc -n default
```

To view the frontend locally using port-forwarding:
```bash
kubectl port-forward svc/frontend 3000:3000
```
Open your browser at `http://localhost:3000` to see the Movie Picture catalog.

---

## Step 8: Clean Up / Teardown AWS Resources

To avoid incurring AWS charges after completing evaluation:

```bash
cd setup/terraform
terraform destroy -auto-approve
```
Confirm all resources (EKS Cluster, VPC, ECR Repositories, Node Groups) are deleted.
