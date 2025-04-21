# Configure AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create VPC (or use existing)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc-flow-logs-demo"
  }
}

# Enable EC2 Instances

# Enable Public Subnets

# Enable Private Subnets

# Enable Public Route Tables

# Enable Private Route Tables

# Enable VPC Flow Logs to S3
resource "aws_flow_log" "vpc_flow_logs" {
  log_destination      = aws_s3_bucket.flow_logs_bucket.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id              = aws_vpc.main.id
}

# S3 Bucket for Flow Logs
resource "aws_s3_bucket" "flow_logs_bucket" {
  bucket = "vpc-flow-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# OpenSearch Domain (Amazon Elasticsearch)
resource "aws_opensearch_domain" "flow_logs_os" {
  domain_name    = "vpc-flow-logs"
  engine_version = "OpenSearch_2.5"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  access_policies = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "es:*",
      "Resource": "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/vpc-flow-logs/*"
    }
  ]
}
POLICY
}

# Lambda Function to Process S3 Logs → OpenSearch
resource "aws_lambda_function" "flow_logs_processor" {
  filename      = "lambda_function.zip"
  function_name = "vpc-flow-logs-to-opensearch"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.8"
  timeout       = 30

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.flow_logs_os.endpoint
    }
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "lambda-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach Policies to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_s3_read" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_opensearch_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonOpenSearchServiceFullAccess"
}

# Trigger Lambda on New S3 Logs
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.flow_logs_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.flow_logs_bucket.arn
}

resource "aws_s3_bucket_notification" "flow_logs_notification" {
  bucket = aws_s3_bucket.flow_logs_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.flow_logs_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

# Output OpenSearch Dashboard URL
output "opensearch_dashboard_url" {
  value = "https://${aws_opensearch_domain.flow_logs_os.endpoint}/_dashboards"
}
