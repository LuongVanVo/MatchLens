# Network module

Provision VPC 3-tier for MatchLens:
- public subnets
- private app subnets
- private db subnets
- internet gateway
- NAT instance
- S3 and DynamoDB gateway endpoints

Rules:
- private_db route tables must not have `0.0.0.0/0`
- dev uses 1 NAT instance
- S3 and DynamoDB gateway endpoints are mandatory from Phase 0