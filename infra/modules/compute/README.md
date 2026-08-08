# Compute module

This module provisions the ECS/Fargate compute layer for MatchLens.

## Resources
- ECS Cluster
- Public ALB
- Backend target group and listener
- Backend ECS task definition and service
- Optional worker ECS task definition and service
- Optional autoscaling for backend and worker

## Notes
- ALB runs in public subnets
- ECS services run in private app subnets
- Backend service is required in Phase 0
- Worker service is optional and should be enabled from Phase 1 onward