#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
  <title>ASG Node Status</title>
  <style>
    body { font-family: sans-serif; background: #0f172a; color: #f8fafc; text-align: center; padding-top: 60px; }
    .box { display: inline-block; background: #1e293b; padding: 30px; border-radius: 8px; border: 1px solid #334155; }
    h1 { color: #38bdf8; margin: 0 0 15px 0; }
    p { font-size: 18px; margin: 5px 0; }
  </style>
</head>
<body>
  <div class="box">
    <h1>Production Web Cluster (ALB + ASG)</h1>
    <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
    <p><strong>Availability Zone:</strong> $AZ</p>
    <p><strong>Status:</strong> Healthy (Serving Traffic)</p>
  </div>
</body>
</html>
EOF
