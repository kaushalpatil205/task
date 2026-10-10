# Task 3: High-Availability Web Cluster (ASG + ALB + CPU Auto Scaling)

## Overview
This task implements a fault-tolerant, scalable web architecture on AWS using an **Application Load Balancer (ALB)** and an **Auto Scaling Group (ASG)** spanning multiple Availability Zones. The cluster features:
1. Dynamic horizontal scaling that scales out instances when cluster average CPU utilization exceeds **70%**.
2. Automated health monitoring and instant self-healing: when an instance becomes unhealthy or fails health checks, the ASG terminates it and launches a fresh replacement to maintain desired capacity.

---

## Architecture Diagram

```mermaid
flowchart TD
    subgraph Internet [Public Traffic]
        CLIENT([Client HTTP Requests])
    end

    subgraph AWS_VPC [VPC: Multi-AZ Infrastructure]
        subgraph Public_Subnets [Public Subnets]
            ALB[Application Load Balancer\nproduct-api-alb\nListens on Port 80]
            ALB_SG[Security Group: alb-sg\nAllow Port 80 from 0.0.0.0/0]
        end

        subgraph ASG_Scope [Auto Scaling Group: product-api-asg\nMin: 1 | Desired: 2 | Max: 4]
            TG[Target Group: product-api-tg\nHealth Check: HTTP / on Port 80\nThreshold: 2 healthy / 3 unhealthy]
            
            subgraph AZ_A [Availability Zone A]
                EC2_1[EC2 Instance 1\nLaunch Template: product-api-lt]
            end

            subgraph AZ_B [Availability Zone B]
                EC2_2[EC2 Instance 2\nLaunch Template: product-api-lt]
            end

            EC2_SG[Security Group: ec2-asg-sg\nAllow Port 80 ONLY from alb-sg]
        end

        subgraph Scaling_Logic [Monitoring & Automation]
            CW[CloudWatch Metric:\nASGAverageCPUUtilization]
            POLICY[Target Tracking Policy:\nscale-out-cpu-70\nTarget Value: 70%]
            HEALTH_CHECK[ELB Health Check:\nAuto-replacement trigger]
        end
    end

    CLIENT --> ALB_SG --> ALB
    ALB --> TG
    TG -->|Route & Balance Traffic| EC2_1
    TG -->|Route & Balance Traffic| EC2_2
    EC2_1 -.-> EC2_SG
    EC2_2 -.-> EC2_SG

    EC2_1 & EC2_2 -.-> CW
    CW --> POLICY -->|CPU > 70% Scale Out| ASG_Scope
    TG --> HEALTH_CHECK -->|Instance Unhealthy -> Launch New| ASG_Scope
```

---

## Repository & Component Layout

```
task-3/
├── scripts/
│   ├── asg-alb-setup.sh         # Complete automation script for VPC, ALB, ASG, and Policy
│   └── cpu-stress-test.sh       # Script to simulate >70% CPU utilization
├── templates/
│   └── user-data.sh             # EC2 bootstrap script for web server & metadata page
├── screenshots/                 # Submission proof screenshots
│   ├── asg-01-launch-template.png
│   ├── asg-02-asg-created.png
│   ├── asg-03-alb-created.png
│   ├── asg-04-target-group-healthy.png
│   ├── asg-05-scaling-policy.png
│   ├── asg-06-site-via-alb.png
│   ├── asg-07-instance-terminated.png
│   └── asg-08-replacement-launched.png
└── README.md
```

---

## Technical Specifications

| Component | Resource Name | Key Configuration |
|---|---|---|
| Launch Template | `product-api-lt` | Amazon Linux 2023 (`t2.micro`), Apache HTTPD, boot metadata page |
| Load Balancer | `product-api-alb` | Internet-facing, dual public subnets (Multi-AZ), listener HTTP:80 |
| Target Group | `product-api-tg` | Protocol: HTTP, Port: 80, Health check path: `/`, Interval: 30s |
| Auto Scaling Group | `product-api-asg` | Min: 1, Max: 4, Desired: 2, Health Check Type: `ELB`, Grace Period: 60s |
| Scaling Policy | `scale-out-cpu-70` | TargetTracking (`ASGAverageCPUUtilization` target 70.0%) |
| Security Isolation | Least Privilege | ALB open to internet; EC2 instances only accept traffic from ALB SG |

---

## Provisioning Guide

### 1. Configure Script Parameters
Open `task-3/scripts/asg-alb-setup.sh` and set your environment variables:
- `REGION`: Target AWS region (e.g., `ap-south-1`)
- `KEY_NAME`: Existing EC2 Key Pair
- `VPC_ID`: Target VPC ID
- `SUBNET_1` & `SUBNET_2`: Two distinct public subnets across different AZs

### 2. Execute Provisioning
```bash
chmod +x task-3/scripts/asg-alb-setup.sh
bash task-3/scripts/asg-alb-setup.sh
```

The script will automatically configure the Security Groups, Launch Template, ALB, Target Group, ASG, and CloudWatch Target Tracking Policy.

---

## Demonstration & Verification Procedures

### Demonstration 1: CPU Scaling Policy (> 70% Load)
To verify that the ASG dynamically scales out when cluster CPU crosses the 70% threshold:

1. Connect to one of the active EC2 instances via SSH or AWS Systems Manager:
   ```bash
   ssh -i <your-key.pem> ec2-user@<instance-public-ip>
   ```

2. Run the stress generator script:
   ```bash
   curl -O https://raw.githubusercontent.com/.../task-3/scripts/cpu-stress-test.sh
   # Or run stress directly:
   sudo yum install -y stress
   stress --cpu $(nproc) --timeout 360s
   ```

3. Observe CloudWatch Metrics and ASG Activity in another terminal:
   ```bash
   aws autoscaling describe-scaling-activities \
     --auto-scaling-group-name product-api-asg \
     --query "Activities[0:3].[Description,StatusCode]" \
     --output table
   ```
   *Result:* CloudWatch triggers an alarm; the ASG automatically increases capacity to launch additional instances to normalize CPU load below 70%.

---

### Demonstration 2: Automatic Replacement of Unhealthy Instances
To verify self-healing and zero-touch instance replacement:

1. Inspect the currently registered instances in the Target Group:
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <TARGET_GROUP_ARN> \
     --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" \
     --output table
   ```

2. Simulate an unexpected instance failure by manually terminating one instance:
   ```bash
   aws ec2 terminate-instances --instance-ids <TARGET_INSTANCE_ID>
   ```

3. Immediately monitor ASG activities:
   ```bash
   aws autoscaling describe-scaling-activities \
     --auto-scaling-group-name product-api-asg \
     --query "Activities[0:2].[Description,Cause]" \
     --output table
   ```
   *Result:* The ASG detects that the instance was terminated or failed health checks, flags it as unhealthy, terminates the node, and automatically triggers:
   > *"Launching a new EC2 instance in response to an unhealthy instance being replaced..."*
   
   The cluster automatically returns to the desired capacity of 2 healthy instances without downtime.

---

## Proof of Submission & Screenshots

All execution proofs are preserved in the [`screenshots/`](screenshots/) directory.

### 1. EC2 Launch Template Provisioned
AWS Console showing `product-api-lt` configured with instance type, security group, and user data.
![Launch Template](screenshots/asg-01-launch-template.png)
*File: `screenshots/asg-01-launch-template.png`*

---

### 2. Auto Scaling Group Configuration
ASG summary showing `product-api-asg` with Min: 1, Max: 4, Desired: 2, and attached subnets.
![ASG Created](screenshots/asg-02-asg-created.png)
*File: `screenshots/asg-02-asg-created.png`*

---

### 3. Application Load Balancer Active
Load Balancer console showing `product-api-alb` in `Active` status across two Availability Zones.
![ALB Created](screenshots/asg-03-alb-created.png)
*File: `screenshots/asg-03-alb-created.png`*

---

### 4. Target Group Health Status
Target Group showing both registered EC2 instances in `Healthy` status on port 80.
![Target Group Healthy](screenshots/asg-04-target-group-healthy.png)
*File: `screenshots/asg-04-target-group-healthy.png`*

---

### 5. Dynamic CPU Target Tracking Policy
ASG Automatic Scaling tab displaying `scale-out-cpu-70` targeting average CPU > 70%.
![Scaling Policy](screenshots/asg-05-scaling-policy.png)
*File: `screenshots/asg-05-scaling-policy.png`*

---

### 6. Application Accessible via ALB DNS
Browser test accessing `http://<alb-dns-name>` displaying instance metadata and responding with HTTP 200.
![Site via ALB](screenshots/asg-06-site-via-alb.png)
*File: `screenshots/asg-06-site-via-alb.png`*

---

### 7. Manual Termination of Instance
EC2 instances console showing one instance transitioning to `shutting-down` / `terminated`.
![Instance Terminated](screenshots/asg-07-instance-terminated.png)
*File: `screenshots/asg-07-instance-terminated.png`*

---

### 8. Self-Healing: Replacement Instance Launched
ASG Activity history showing the event launching a replacement instance to maintain desired capacity.
![Replacement Launched](screenshots/asg-08-replacement-launched.png)
*File: `screenshots/asg-08-replacement-launched.png`*
