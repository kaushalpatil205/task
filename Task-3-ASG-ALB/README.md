# Task-3: ASG + ALB + Auto Scaling

## 📖 Architecture Overview
This task demonstrates a highly available, self-healing Application Tier using EC2 Virtual Machines. 
Traffic is distributed across multiple Availability Zones using an **Application Load Balancer (ALB)**, while an **Auto Scaling Group (ASG)** ensures the cluster dynamically scales out under high CPU load and automatically replaces failed instances.

**Key Implementations:**
* **Launch Template:** Bootstraps Amazon Linux 2023 instances with an Apache web server that dynamically outputs its Instance ID and Availability Zone to prove Load Balancing.
* **Security Groups:** The EC2 instances are strictly isolated and only accept port 80 traffic originating from the ALB Security Group.
* **Dynamic Auto Scaling:** A Target Tracking Policy scales the ASG out if the average CPU utilization exceeds 70%.
* **Self-Healing:** The ASG is tied to the ALB's health checks. If an instance fails or is terminated, it is automatically detected and replaced to maintain the Desired Capacity.

## 🚀 Execution Guide & Commands Log

The infrastructure was provisioned autonomously using `scripts/asg-alb-setup.sh`. The script dynamically fetches the active default VPC, auto-remediates missing Availability Zone subnets, and fetches the latest region-specific Amazon Linux 2023 AMI via AWS Systems Manager (SSM).

Below are the core AWS CLI commands executed by the automation:

### 1. Provision Security Groups
```bash
# ALB Security Group (Internet Facing)
aws ec2 create-security-group --group-name alb-sg-1791638382 --description "Allow HTTP from internet" --vpc-id vpc-028724486a6015b2e
aws ec2 authorize-security-group-ingress --group-id sg-02516ebd33d6eb020 --protocol tcp --port 80 --cidr 0.0.0.0/0

# EC2 Security Group (Isolated, only accepts traffic from ALB)
aws ec2 create-security-group --group-name ec2-asg-sg-1791638382 --description "Allow HTTP only from ALB" --vpc-id vpc-028724486a6015b2e
aws ec2 authorize-security-group-ingress --group-id sg-06e12ef993ef92958 --protocol tcp --port 80 --source-group sg-02516ebd33d6eb020
```

### 2. Create Launch Template & Target Group
```bash
# Dynamically fetch the latest Amazon Linux 2023 AMI from SSM
AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 --query 'Parameters[0].Value' --output text)

# Create Launch Template with bootstrap UserData
aws ec2 create-launch-template --launch-template-name product-api-lt-1791638382 --launch-template-data file://config.json

# Create HTTP Target Group
aws elbv2 create-target-group --name product-api-tg-1791638382 --protocol HTTP --port 80 --vpc-id vpc-028724486a6015b2e --health-check-path "/"
```

### 3. Deploy Application Load Balancer
```bash
# Deployed across two different Availability Zones (ap-south-1b and ap-south-1c)
aws elbv2 create-load-balancer --name product-api-alb-1791638382 --subnets subnet-0d7adbc7f76de1b61 subnet-0dedbc5b12f1afd97 --security-groups sg-02516ebd33d6eb020
aws elbv2 create-listener --load-balancer-arn <ALB_ARN> --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=<TG_ARN>
```

### 4. Deploy Auto Scaling Group & Scaling Policy
```bash
# Create ASG
aws autoscaling create-auto-scaling-group   --auto-scaling-group-name product-api-asg-1791638382   --launch-template LaunchTemplateId=lt-08a10389682060ca3,Version=$Latest   --min-size 1 --max-size 4 --desired-capacity 2   --vpc-zone-identifier "subnet-0d7adbc7f76de1b61,subnet-0dedbc5b12f1afd97"   --target-group-arns <TG_ARN>   --health-check-type ELB --health-check-grace-period 60

# Apply CPU > 70% Target Tracking Scaling Policy
aws autoscaling put-scaling-policy   --auto-scaling-group-name product-api-asg-1791638382   --policy-name scale-out-cpu-70   --policy-type TargetTrackingScaling   --target-tracking-configuration '{"PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"}, "TargetValue": 70.0}'
```

---

## 📸 Execution Screenshots

### 1. Load Balancer Distributing Traffic
The ALB successfully routing traffic to the EC2 instances across different AZs.
![ALB Traffic](screenshots/asg-01-alb-traffic.png)

### 2. CPU Auto Scaling Policy
The Target Tracking scaling policy configured to trigger when CPU > 70%.
![Scaling Policy](screenshots/asg-02-scaling-policy.png)

### 3. Unhealthy Instance Replacement (Self-Healing)
Proof of the ASG automatically detecting a terminated instance and successfully launching a replacement.
![Auto Replacement](screenshots/asg-03-auto-replacement.png)

---

## 🧹 Environment Cleanup

To prevent ongoing EC2 instance and Load Balancer hourly charges, destroy the infrastructure using either the AWS Console or the AWS CLI commands below:

**AWS CLI Cleanup Commands:**
```bash
# 1. Delete the Auto Scaling Group (using --force-delete automatically terminates running EC2 instances)
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name product-api-asg-1791638382 --force-delete

# 2. Delete the Application Load Balancer
aws elbv2 delete-load-balancer --load-balancer-arn <YOUR_ALB_ARN>

# 3. Delete the Target Group
aws elbv2 delete-target-group --target-group-arn <YOUR_TG_ARN>

# 4. Delete the Launch Template
aws ec2 delete-launch-template --launch-template-name product-api-lt-1791638382

# 5. Delete the Security Groups (Delete EC2 first, as ALB SG is referenced by it)
aws ec2 delete-security-group --group-id sg-06e12ef993ef92958
aws ec2 delete-security-group --group-id sg-02516ebd33d6eb020
```