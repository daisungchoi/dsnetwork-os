import boto3
import gzip
import json
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
import os

# OpenSearch Config
OPENSEARCH_ENDPOINT = os.environ['OPENSEARCH_ENDPOINT']
REGION = 'us-east-1'
INDEX_NAME = 'vpc-flow-logs'

# AWS Auth for OpenSearch
session = boto3.Session()
credentials = session.get_credentials()
awsauth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    REGION,
    'es',
    session_token=credentials.token
)

# OpenSearch Client
opensearch = OpenSearch(
    hosts=[{'host': OPENSEARCH_ENDPOINT, 'port': 443}],
    http_auth=awsauth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection
)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        # Download and decompress log file
        response = s3.get_object(Bucket=bucket, Key=key)
        log_data = gzip.decompress(response['Body'].read()).decode('utf-8')
        
        # Parse and index each log entry
        for line in log_data.splitlines():
            log_entry = json.loads(line)
            opensearch.index(
                index=INDEX_NAME,
                body=log_entry
            )
    
    return {
        'statusCode': 200,
        'body': json.dumps('VPC Flow Logs processed successfully!')
    }
