#!/usr/bin/env bash

# Requires installation of aws cli, jq & terraform

set -e

# Validate input
if [ -z "$ENV" ]; then
  echo "ENV variable is empty"
  exit 1
fi

if [ -z "$STACK" ]; then
  echo "STACK variable is empty"
  exit 1
fi

if [ "$AUTO_APPROVE" == "1" ]; then
  echo "AUTO_APPROVE set, resource creation will be automatic"
else
  echo "AUTO_APPROVE not set, resource creation must be approved"
fi

region="${AWS_DEFAULT_REGION:-$(aws configure get region || echo null)}"

if [ $region = "null" ]; then
  echo "No region set, use either AWS_DEFAULT_REGION env var or .aws/config file."
  exit 1
fi

account_id=$(aws --region $region sts get-caller-identity --query Account --output text)
account_alias=$(aws --output json --region $region iam list-account-aliases | jq .AccountAliases[0] | tr -d '"')
if [ $account_alias = "null" ]; then
  echo "No alias set, using account id in bucket name"
  account_alias=$account_id
fi

bucket_name="${account_alias}-tf-state"
key_name="env/${ENV}/stack/${STACK}.tfstate"
table_name="${ENV}_${STATE_NAME}_tf_state_lock"

# Create S3 bucket if it does not exist
check_bucket_exists=$(aws --output json --region $region s3api list-buckets | jq "[ .Buckets[].Name ] | index(\"${bucket_name}\")")
if [ "$check_bucket_exists" != "$null" ]
then
  echo "Bucket $bucket_name already exists"
else
  echo "Bucket $bucket_name doesn't exist - creating"

  if [ "$AUTO_APPROVE" != "1" ]; then read -p "Press enter to continue"; fi

  aws s3api create-bucket \
    --region "${region}" \
    --create-bucket-configuration LocationConstraint="${region}" \
    --bucket "${bucket_name}"

  echo "Bucket $bucket_name created"
fi

# Create a DynamoDB table if it does not exist
check_table_exists=$(aws --output json --region $region list-tables | jq ".TableNames | index(\"${table_name}\")"
if [ "$check_table_exists" != "null" ]
then
  echo "Table $table_name already exist"
else
  echo "Table $table_name doesn't exist - creating $table_name"

  if [ "$AUTO_APPROVE" != "1" ]; then read -p "Press enter to continue"; fi

  aws dynamodb create-table \
    --region "${region}" \
    --table-name "${table_name}"\
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1
  echo "Table $table_name created"
fi

terraform init \
  -backend-config="region=$region" \
  -backend-config="bucket=$bucket_name" \
  -backend-config="key=$key_name" \
  -backend-config="dynamo_table=$table_name"
