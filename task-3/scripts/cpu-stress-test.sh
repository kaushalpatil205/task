#!/bin/bash
# Script to simulate high CPU utilization (>70%) to trigger Auto Scaling
# Run this directly on an ASG EC2 instance via SSH or Systems Manager Run Command

echo "==> Installing EPEL and stress utility..."
if command -v amazon-linux-extras &> /dev/null; then
  sudo amazon-linux-extras install epel -y
fi
sudo yum install -y stress || sudo dnf install -y stress

CPU_CORES=$(nproc)
echo "==> Running stress test on $CPU_CORES cores for 360 seconds..."
echo "==> Target: Drive CPU utilization over 70% threshold"
stress --cpu "$CPU_CORES" --timeout 360s

echo "==> Stress test finished. Monitor ASG scaling activities via AWS CLI or Console."
