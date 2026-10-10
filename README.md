# DevOps Infrastructure & Automation Hands-On Tasks

This repository contains production-ready implementations, configuration scripts, manifests, and documentation for three core DevOps infrastructure tasks:

1. **Task-1: CI/CD**: Automated CI/CD Pipeline (GitHub Actions → Docker → Amazon ECR → Amazon EKS)
2. **Task-2: CloudFront**: Secure Static Website Delivery (Amazon CloudFront + S3 with Origin Access Control)
3. **Task-3: ASG + ALB**: High-Availability & Self-Healing Web Cluster (ASG + ALB with Dynamic CPU Auto Scaling)

---

## Repository Navigation & Path Directory

Each task is self-contained within its own directory, containing all associated code, manifests, provisioning scripts, automated architecture diagrams, a dedicated in-depth `README.md`, and a dedicated `screenshots/` directory for submission proofs.

| Task | Primary Objective | Code / Manifests Path | Detailed Guide | Proof of Submission |
|---|---|---|---|---|
| **CI/CD: CI/CD** | Automated testing, Docker packaging, ECR registry push & EKS Kubernetes deployment | [`ci-cd/`](ci-cd/) | [`Task-1-CI-CD/README.md`](Task-1-CI-CD/README.md) | [`Task-1-CI-CD/screenshots/`](Task-1-CI-CD/screenshots/) |
| **Task-2: CloudFront** | S3 private static hosting, CloudFront CDN edge delivery, OAC security lock & cache invalidation | [`cloudfront/`](cloudfront/) | [`Task-2-CloudFront/README.md`](Task-2-CloudFront/README.md) | [`Task-2-CloudFront/screenshots/`](Task-2-CloudFront/screenshots/) |
| **Task-3: ASG + ALB** | Multi-AZ Application Load Balancer, Launch Template, ASG CPU >70% scaling & automatic instance replacement | [`asg-alb/`](asg-alb/) | [`Task-3-ASG-ALB/README.md`](Task-3-ASG-ALB/README.md) | [`Task-3-ASG-ALB/screenshots/`](Task-3-ASG-ALB/screenshots/) |

---

## Directory Structure

```
task/
├── .github/
│   └── workflows/
│       └── ci-cd.yml             # Global GitHub Actions workflow for CI/CD
│
├── Task-1-CI-CD/                       # CI/CD: CI/CD Pipeline
│   ├── README.md                 # In-depth CI/CD guide with architecture & embedded proofs
│   ├── app/                      # Node.js product REST microservice
│   │   ├── Dockerfile            # Production multi-stage Alpine Dockerfile
│   │   ├── package.json          # Dependencies & test runners
│   │   ├── src/index.js          # REST API & /health probe endpoint
│   │   └── tests/app.test.js     # Jest unit test suite
│   ├── k8s/                      # Kubernetes deployment & service manifests
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── screenshots/              # CI/CD proof captures (cicd-01 to cicd-06)
│
├── Task-2-CloudFront/                       # Task-2: CloudFront + S3 Static Website
│   ├── README.md                 # In-depth Task 2 guide with architecture & embedded proofs
│   ├── scripts/
│   │   └── cloudfront-setup.sh   # Bash automation script (S3, OAC, Distribution, Policy)
│   ├── static/                   # Website content (index.html, error.html)
│   ├── policy/
│   │   └── s3-oac-policy.json    # Bucket policy enforcing CloudFront OAC access
│   └── screenshots/              # Task 2 proof captures (cf-01 to cf-07)
│
├── Task-3-ASG-ALB/                       # Task-3: ASG + ALB + Auto Scaling
│   ├── README.md                 # In-depth Task 3 guide with architecture & embedded proofs
│   ├── scripts/
│   │   ├── asg-alb-setup.sh      # Bash automation script (VPC, ALB, TG, ASG, Policy)
│   │   └── cpu-stress-test.sh    # Script to simulate high CPU utilization (>70%)
│   ├── templates/
│   │   └── user-data.sh          # EC2 bootstrap script for web server
│   └── screenshots/              # Task 3 proof captures (asg-01 to asg-08)
│
└── README.md                     # Main repository navigation index (this file)
```

---

## Tasks Summary

### [Task-1: CI/CD](Task-1-CI-CD/README.md)
- **Goal**: Implement a non-breaking delivery pipeline triggered on Git pushes.
- **Workflow Steps**:
  1. **Run Tests**: Installs dependencies and runs Jest unit tests covering positive and negative API paths.
  2. **Build & Push**: Logs into Amazon ECR via IAM credentials, builds an Alpine-based Docker container, tags it with the immutable Git commit SHA and `latest`, and pushes both tags.
  3. **Deploy to K8s**: Authenticates with Amazon EKS, substitutes the dynamic image tag into Kubernetes manifests, applies Deployment and LoadBalancer Service configurations, and verifies rollout completion.
- **Microservice**: Node.js Express Product API exposing `/health` for Kubernetes probes and `/products` for CRUD operations.
- **Full Guide**: Refer to [`Task-1-CI-CD/README.md`](Task-1-CI-CD/README.md).

---

### [Task-2: CloudFront](Task-2-CloudFront/README.md)
- **Goal**: Host a static web portal on Amazon S3 with global CDN caching and strict access control.
- **Security & Delivery Highlights**:
  1. **S3 Hardening**: All 4 Block Public Access toggles are permanently enabled.
  2. **Origin Access Control (OAC)**: Replaces legacy OAI; signs requests from CloudFront to S3 using AWS SigV4.
  3. **Direct S3 Restriction**: Direct HTTP/S attempts to the S3 bucket endpoint return `403 Access Denied`.
  4. **Custom 404 Routing**: S3 missing keys route through CloudFront to custom `error.html`.
  5. **Cache Invalidation**: On asset deployment, invalidation requests (`/*`) clear edge caches globally.
- **Full Guide**: Refer to [`Task-2-CloudFront/README.md`](Task-2-CloudFront/README.md).

---

### [Task-3: ASG + ALB](Task-3-ASG-ALB/README.md)
- **Goal**: Provision a highly-available, self-healing web server fleet across multiple Availability Zones.
- **Architecture Highlights**:
  1. **Security Isolation**: Internet traffic only enters the Application Load Balancer (ALB SG); EC2 web servers only accept traffic from the ALB SG.
  2. **Launch Template**: Configures Amazon Linux 2023 instances with an automated bootstrap script serving instance metadata.
  3. **Target Group & ALB**: Distributes traffic across subnets and runs continuous HTTP health checks on `/`.
  4. **CPU Auto Scaling**: CloudWatch Target Tracking scaling policy monitors `ASGAverageCPUUtilization` and dynamically adds instances when average CPU utilization exceeds **70%**.
  5. **Self-Healing Replacement**: Automatically detects terminated or unhealthy instances via ELB health checks and launches replacements to maintain the desired capacity of 2 nodes.
- **Full Guide**: Refer to [`Task-3-ASG-ALB/README.md`](Task-3-ASG-ALB/README.md).

---

## Proof of Submission Master Index

For submission, each task folder contains an isolated `screenshots/` directory. Capture each proof and place the file in the matching path below:

### CI/CD Screenshots ([`Task-1-CI-CD/screenshots/`](Task-1-CI-CD/screenshots/))
- `cicd-01-repo-secrets.png`: GitHub repository Secrets configuration with OIDC (`AWS_ROLE_ARN`, `EKS_CLUSTER_NAME`).
- `cicd-02-pipeline-running.png`: GitHub Actions tab showing triggered pipeline execution.
- `cicd-03-tests-passed.png`: Expanded "Run Tests" job output showing all unit tests green.
- `cicd-04-ecr-image.png`: AWS ECR console showing the uploaded image tagged with Git SHA.
- `cicd-05-k8s-deploy.png`: Terminal output of `kubectl get pods -n production` showing healthy running pods.
- `cicd-06-rollout-done.png`: GitHub Actions deploy job output showing rollout successfully completed.

### Task 2 Screenshots ([`Task-2-CloudFront/screenshots/`](Task-2-CloudFront/screenshots/))
- `cf-01-bucket-created.png`: S3 bucket showing all 4 Public Access Block settings enabled.
- `cf-02-files-uploaded.png`: S3 console objects tab showing `index.html` and `error.html`.
- `cf-03-bucket-policy.png`: S3 permissions tab showing OAC bucket policy attached.
- `cf-04-distribution-deployed.png`: CloudFront distributions list showing status `Deployed`.
- `cf-05-site-loads-via-cdn.png`: Web browser rendering portal over HTTPS via `*.cloudfront.net`.
- `cf-06-direct-s3-blocked.png`: Web browser or curl showing `403 Forbidden` when attempting direct S3 access.
- `cf-07-cache-invalidation.png`: AWS CLI or console showing completed cache invalidation.

### Task 3 Screenshots ([`Task-3-ASG-ALB/screenshots/`](Task-3-ASG-ALB/screenshots/))
- `asg-01-launch-template.png`: EC2 Launch Template console showing `product-api-lt`.
- `asg-02-asg-created.png`: Auto Scaling Group console showing `product-api-asg` with desired=2.
- `asg-03-alb-created.png`: Load Balancers console showing `product-api-alb` in `Active` status.
- `asg-04-target-group-healthy.png`: Target Group targets tab showing both registered instances `Healthy`.
- `asg-05-scaling-policy.png`: ASG Automatic Scaling tab displaying the CPU 70% TargetTracking policy.
- `asg-06-site-via-alb.png`: Web browser accessing ALB DNS name and returning HTTP 200 with instance ID.
- `asg-07-instance-terminated.png`: EC2 console showing manual termination of an active instance.
- `asg-08-replacement-launched.png`: ASG Activity history displaying automatic launch of replacement instance.

---

## Environment Prerequisites

- **AWS Region**: Default scripts use `ap-south-1` (Mumbai). Update variables in scripts if using another region.
- **AWS CLI**: Version 2.x configured with administrative credentials (`aws configure`).
- **Kubernetes**: `kubectl` configured with cluster access context.
- **Node.js**: Version 18.x or later installed locally for app testing.

---

## 🔒 Security & Authentication Architecture

**Note on AWS Authentication Strategy:**
The GitHub Actions pipelines in this repository are configured to use standard IAM Access Keys and Session Tokens (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) for simplicity and ease of testing.

**Best Practice Implementation:**
As an alternative, **OpenID Connect (OIDC)** can be used to securely assume an IAM role without managing long-lived credentials. The IAM Trust Policy mapped to the OIDC provider would use the following condition to restrict access specifically to this repository:
```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
  },
  "StringLike": {
    "token.actions.githubusercontent.com:sub": "repo:kaushalpatil205/task:*"
  }
}
```
*The infrastructure code and IAM configurations for this exact OIDC implementation are preserved in the `Task-1-CI-CD/iam/` directory for review.*

## 🏗️ CI/CD Overview: Node.js Microservice

The application deployed in CI/CD is a Node.js/Express backend REST API. It acts as a headless data provider, exposing a `GET /api/products` JSON endpoint. 

The `ci-cd/` directory is structured as follows:
*   `app/`: Contains the Node.js API code, Jest unit tests, and the multi-stage `Dockerfile`.
*   `k8s/`: Contains the Kubernetes manifests (`deployment.yaml` and `service.yaml`) used to provision the pods and AWS LoadBalancer.
*   `iam/`: Contains the security policies, specifically the OIDC Federation Trust Policy.
