#!/bin/bash
# ASG + ALB setup with CPU-based auto-scaling
# Run: bash scripts/asg-alb-setup.sh

set -e

REGION="ap-south-1"
# Amazon Linux 2023 in ap-south-1
AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 --query "Parameters[0].Value" --output text) 
INSTANCE_TYPE="t3.micro"
SUFFIX=$(date +%s)

echo "==> Fetching Default VPC..."
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)

echo "==> Validating Subnets..."
SUBNET_LIST=($(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[*].SubnetId" --output text))

SUBNET_1=${SUBNET_LIST[0]}
SUBNET_2=${SUBNET_LIST[1]}

# Auto-remediate if the default VPC is missing a second subnet
if [ -z "$SUBNET_2" ]; then
    echo "    Detected only 1 subnet in VPC. Automatically provisioning a 2nd Subnet in ap-south-1b..."
    SUBNET_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.31.16.0/20 --availability-zone ap-south-1b --query 'Subnet.SubnetId' --output text)
    
    echo "    Enabling Public IPs for new Subnet..."
    aws ec2 modify-subnet-attribute --subnet-id $SUBNET_2 --map-public-ip-on-launch
    sleep 2
fi

echo "    VPC ID  : $VPC_ID"
echo "    Subnet 1: $SUBNET_1"
echo "    Subnet 2: $SUBNET_2"

# ---- Security Groups ----
echo "==> Creating security group for ALB"
ALB_SG=$(aws ec2 create-security-group \
  --group-name "alb-sg-$SUFFIX" \
  --description "Allow HTTP from internet" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "==> Creating security group for EC2 instances"
EC2_SG=$(aws ec2 create-security-group \
  --group-name "ec2-asg-sg-$SUFFIX" \
  --description "Allow HTTP only from ALB" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

# instances only accept traffic from the ALB security group
aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG" \
  --protocol tcp --port 80 --source-group "$ALB_SG"

# ---- Launch Template ----
echo "==> Creating Launch Template"

USER_DATA=$(base64 <<'USERDATAEOF'
#!/bin/bash
yum update -y
yum install -y httpd stress
systemctl start httpd
systemctl enable httpd
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
echo "<h1>Highly Available Web Cluster</h1><p>Served from Instance: <b>$INSTANCE_ID</b></p><p>Availability Zone: <b>$AZ</b></p>" > /var/www/html/index.html
USERDATAEOF
)

LT_ID=$(aws ec2 create-launch-template \
  --launch-template-name "product-api-lt-$SUFFIX" \
  --version-description "v1" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"$INSTANCE_TYPE\",
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
echo "==> Creating Application Load Balancer (ALB)"
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "product-api-alb-$SUFFIX" \
  --subnets "$SUBNET_1" "$SUBNET_2" \
  --security-groups "$ALB_SG" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

echo "    ALB ARN: $ALB_ARN"

# ---- Target Group ----
echo "==> Creating Target Group"
TG_ARN=$(aws elbv2 create-target-group \
  --name "product-api-tg-$SUFFIX" \
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
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" > /dev/null

# ---- Auto Scaling Group ----
echo "==> Creating Auto Scaling Group (ASG)"
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "product-api-asg-$SUFFIX" \
  --launch-template "LaunchTemplateId=$LT_ID,Version=\$Latest" \
  --min-size 1 \
  --max-size 4 \
  --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_1,$SUBNET_2" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 60 \
  --tags Key=Name,Value=product-api-asg,PropagateAtLaunch=true

# ---- Scaling Policy: CPU > 70% ----
echo "==> Creating CPU-based Target Tracking scaling policy (> 70%)"
POLICY_ARN=$(aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "product-api-asg-$SUFFIX" \
  --policy-name "scale-out-cpu-70" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 70.0,
  }' \
  --query 'PolicyARN' --output text)

echo "    Policy ARN: $POLICY_ARN"

echo "==> Waiting for ALB to become active (takes about 2-3 minutes)..."
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' --output text)

echo ""
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo "  ALB DNS : http://$ALB_DNS"
echo "  ASG     : product-api-asg-$SUFFIX (min=1, max=4, desired=2)"
echo "  Policy  : Scale out when avg CPU > 70%"
echo ""
echo "To test high availability and unhealthy replacement:"
echo "  1. Open the EC2 Console"
echo "  2. Terminate any running instance named 'product-api-instance'"
echo "  3. Watch the ASG automatically detect it as unhealthy and launch a replacement!"
