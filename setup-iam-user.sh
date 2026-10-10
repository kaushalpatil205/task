#!/bin/bash
aws iam create-user --user-name github-actions-deployer 2>/dev/null || true
aws iam attach-user-policy --user-name github-actions-deployer --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam attach-user-policy --user-name github-actions-deployer --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam put-user-policy --user-name github-actions-deployer --policy-name eks-full-access --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["eks:DescribeCluster","eks:ListClusters","eks:AccessKubernetesApi"],"Resource":"*"}]}'
aws iam create-access-key --user-name github-actions-deployer
