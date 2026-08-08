# security module

This module provisions IAM roles, IAM policies, GitHub OIDC federation, Secrets Manager secrets, Security Hub, AWS Config, and GuardDuty for MatchLens.

## Resources
- ECS task role for backend
- ECS task role for worker
- Lambda roles for dispatcher, status updater, and mediaconvert trigger
- MediaConvert service role
- Glue job role
- GitHub Actions OIDC provider and deploy role
- JWT keypair secret
- CloudFront signing key secret
- Security Hub
- AWS Config
- GuardDuty

## Notes
- OIDC provider is intentionally managed in this module because it belongs to the trust boundary and IAM federation layer.
- Queue ARNs are derived by naming convention to avoid circular dependency with `messaging`.
- RDS credentials secret is created by `database` and passed in as `db_secret_arn`.