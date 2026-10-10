#!/bin/bash
# ASG + ALB setup with CPU-based auto-scaling
# Run: bash asg-alb-setup.sh
# Requirements: AWS CLI configured, existing VPC with public subnets

set -e

REGION="ap-south-1"
AMI_ID="ami-0f58b397bc5c1f2e8"       # Amazon Linux 2023 in ap-south-1
INSTANCE_TYPE="t2.micro"
KEY_NAME="your-key-pair"              # replace with your key pair name
VPC_ID="vpc-xxxxxxxxx"               # replace with your VPC ID
SUBNET_1="subnet-aaaaaaaa"           # replace with subnet 1 (AZ-a)
SUBNET_2="subnet-bbbbbbbb"           # replace with subnet 2 (AZ-b)

# ---- Security Groups ----
echo "==> Creating security group for ALB"
ALB_SG=$(aws ec2 create-security-group \
  --group-name "alb-sg" \
  --description "Allow HTTP from internet" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "==> Creating security group for EC2 instances"
EC2_SG=$(aws ec2 create-security-group \
  --group-name "ec2-asg-sg" \
  --description "Allow HTTP only from ALB" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

# instances only accept traffic from the ALB security group
aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG" \
  --protocol tcp --port 80 --source-group "$ALB_SG"

# ---- Launch Template ----
echo "==> Creating Launch Template"

USER_DATA=$(base64 <<'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
# simple health-check page
echo "<h1>Instance: $(hostname -f)</h1>" > /var/www/html/index.html
EOF
)

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "product-api-lt" \
  --version-description "v1" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
    \"KeyName\": \"$KEY_NAME\",
    \"SecurityGroupIds\": [\"$EC2_SG\"],
    \"UserData\": \"$USER_DATA\",
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [{\"Key\": \"Name\", \"Value\": \"product-api-instance\"}]
    }]
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)

echo "    Launch Template ID: $LT_ID"

# ---- Application Load Balancer ----
echo "==> Creating ALB"
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "product-api-alb" \
  --subnets "$SUBNET_1" "$SUBNET_2" \
  --security-groups "$ALB_SG" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

echo "    ALB ARN: $ALB_ARN"

# ---- Target Group ----
echo "==> Creating Target Group"
TG_ARN=$(aws elbv2 create-target-group \
  --name "product-api-tg" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --health-check-protocol HTTP \
  --health-check-path "/" \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --health-check-interval-seconds 30 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

echo "    Target Group ARN: $TG_ARN"

# ---- ALB Listener ----
echo "==> Creating ALB Listener"
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN"

# ---- Auto Scaling Group ----
echo "==> Creating Auto Scaling Group"
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "product-api-asg" \
  --launch-template "LaunchTemplateId=$LT_ID,Version=\$Latest" \
  --min-size 1 \
  --max-size 4 \
  --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_1,$SUBNET_2" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 60 \
  --tags Key=Name,Value=product-api-asg,PropagateAtLaunch=true

# ---- Scaling Policy: CPU > 70% → scale out ----
echo "==> Creating CPU-based scaling policy"
POLICY_ARN=$(aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "product-api-asg" \
  --policy-name "scale-out-cpu-70" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 70.0,
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }' \
  --query 'PolicyARN' --output text)

echo "    Policy ARN: $POLICY_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' --output text)

echo ""
echo "Done!"
echo "  ALB DNS: http://$ALB_DNS"
echo "  ASG    : product-api-asg (min=1, max=4, desired=2)"
echo "  Policy : scale when avg CPU > 70%"
echo ""
echo "To test unhealthy instance replacement:"
echo "  1. Terminate any running instance manually"
echo "  2. Watch ASG automatically launch a replacement"
echo "  aws autoscaling describe-scaling-activities --auto-scaling-group-name product-api-asg"
