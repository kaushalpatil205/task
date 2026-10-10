#!/bin/bash
# CloudFront + S3 static website setup
# Run: bash scripts/cloudfront-setup.sh
# Requirements: AWS CLI configured with appropriate permissions

set -e

BUCKET_NAME="production-portal-$(date +%s)"
REGION="ap-south-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "==> Creating S3 bucket: $BUCKET_NAME"
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

# block all public access — CloudFront will access via OAC, not public URLs
echo "==> Blocking all public access on S3"
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# upload the beautiful website files we pre-created
echo "==> Uploading static website files"
aws s3 cp static/index.html s3://"$BUCKET_NAME"/index.html
aws s3 cp static/error.html s3://"$BUCKET_NAME"/error.html

# create Origin Access Control
echo "==> Creating Origin Access Control (OAC)"
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    Name=MyOAC-$(date +%s),OriginAccessControlOriginType=s3,SigningBehavior=always,SigningProtocol=sigv4,Description="OAC for static site" \
  --query 'OriginAccessControl.Id' --output text)

echo "    OAC ID: $OAC_ID"

# create the CloudFront distribution
echo "==> Creating CloudFront distribution"
DIST_CONFIG=$(cat <<JSON
{
  "CallerReference": "cf-dist-$(date +%s)",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3Origin",
        "DomainName": "${BUCKET_NAME}.s3.${REGION}.amazonaws.com",
        "S3OriginConfig": { "OriginAccessIdentity": "" },
        "OriginAccessControlId": "${OAC_ID}"
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3Origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    }
  },
  "DefaultRootObject": "index.html",
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/error.html",
        "ResponseCode": "404",
        "ErrorCachingMinTTL": 10
      },
      {
        "ErrorCode": 403,
        "ResponsePagePath": "/error.html",
        "ResponseCode": "404",
        "ErrorCachingMinTTL": 10
      }
    ]
  },
  "Enabled": true,
  "Comment": "Static site distribution"
}
JSON
)

DIST_OUTPUT=$(aws cloudfront create-distribution --distribution-config "$DIST_CONFIG")
DIST_ID=$(echo "$DIST_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Distribution']['Id'])")
DIST_DOMAIN=$(echo "$DIST_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Distribution']['DomainName'])")

echo "    Distribution ID: $DIST_ID"
echo "    Domain: https://$DIST_DOMAIN"

# attach bucket policy so CloudFront OAC can read from S3
echo "==> Attaching S3 bucket policy for OAC"
POLICY=$(cat <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontOAC",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}"
        }
      }
    }
  ]
}
POLICY
)

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "$POLICY"

echo ""
echo "Setup complete!"
echo "  Bucket  : $BUCKET_NAME"
echo "  Site URL: https://$DIST_DOMAIN"
echo "  Dist ID : $DIST_ID"
echo ""
echo "Note: It will take about 3-5 minutes for CloudFront to fully deploy globally."
