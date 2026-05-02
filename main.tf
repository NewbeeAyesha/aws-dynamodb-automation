# 1. PROVIDER
provider "aws" {
  region = "us-east-1"
}

# 2. S3 BUCKET (The archive)
resource "aws_s3_bucket" "log_archive" {
  bucket = "ayesha-automated-logs-2026"
}

# 3. DYNAMODB (The database)
resource "aws_dynamodb_table" "records_table" {
  name           = "MyRecordsTable_Automated"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "RecordID"

  attribute {
    name = "RecordID"
    type = "S"
  }
}

# 4. LAMBDA ROLE & PERMISSIONS
resource "aws_iam_role" "lambda_role" {
  name = "Lambda_Automation_Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_dynamodb_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.records_table.arn
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# 5. FIREHOSE ROLE (The "Fix" version)
resource "aws_iam_role" "firehose_role" {
  name = "Firehose_Automation_Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { 
        Service = ["firehose.amazonaws.com", "logs.amazonaws.com"] 
      }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "firehose_s3_access"
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = [aws_s3_bucket.log_archive.arn, "${aws_s3_bucket.log_archive.arn}/*"]
    }]
  })
}

# 6. KINESIS FIREHOSE
resource "aws_kinesis_firehose_delivery_stream" "automated_stream" {
  name        = "AutomatedLogStreamToS3"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.log_archive.arn
    compression_format = "GZIP"
  }
}

# 7. CLOUDWATCH SUBSCRIPTION (The Connection)
resource "aws_cloudwatch_log_subscription_filter" "firehose_filter" {
  name            = "FirehoseSubscription"
  log_group_name  = "/aws/lambda/AutomatedStoreRecordFunction"
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.automated_stream.arn
  role_arn        = aws_iam_role.firehose_role.arn
}
# 8. Allow the role to Put Records into the Firehose
resource "aws_iam_role_policy" "firehose_put_policy" {
  name = "firehose_put_access"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
        Effect   = "Allow"
        Resource = aws_kinesis_firehose_delivery_stream.automated_stream.arn
      }
    ]
  })
}