# AWS Containerized Microservices Infrastructure

This repository contains a Turborepo monorepo with containerized Express services deployed to AWS Fargate, complete with infrastructure as code and monitoring setup.

## Project Structure

```
.
├── apps/
│   ├── web-service/     # Frontend Express service
│   └── api-service/     # Backend API service
├── infrastructure/      # Terraform configurations
├── monitoring/         # Monitoring configurations
└── scripts/           # Utility scripts
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+
- Docker
- Terraform 1.5+
- pnpm (for Turborepo)

## Local Development

1. Install dependencies:
```bash
pnpm install
```

2. Start local development environment:
```bash
# Start Postgres in Docker
docker compose up db

# Start all services
pnpm dev

# Or start individual services
pnpm dev --filter web-service
pnpm dev --filter api-service
```

3. Access local services:
- Web Service: http://localhost:3000
- API Service: http://localhost:3001
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3100

## Infrastructure Setup

1. Initialize Terraform:
```bash
cd infrastructure
terraform init
```

2. Create a `terraform.tfvars` file:
```hcl
environment         = "dev"
aws_region         = "us-east-1"
vpc_cidr           = "10.0.0.0/16"
database_password  = "your-secure-password"
```

3. Apply infrastructure:
```bash
terraform plan
terraform apply
```

## Deployment

Push changes to trigger the CI/CD pipeline:

```bash
# Deploy to dev
git push origin dev

# Deploy to staging
git push origin staging

# Deploy to production
git push origin main
```

## Monitoring

### Logs
- All service logs are shipped to CloudWatch Logs
- Log groups follow pattern: /{environment}/{service-name}
- Structured logging with correlation IDs enabled

### Metrics
- Prometheus metrics available at /metrics for each service
- Grafana dashboards pre-configured for:
  - Service health
  - Request metrics
  - Database connections
  - Container metrics

### Accessing Dashboards
```bash
# Get Grafana URL
aws cloudformation describe-stacks \
  --stack-name monitoring \
  --query 'Stacks[0].Outputs[?OutputKey==`GrafanaURL`].OutputValue' \
  --output text
```

## Common Tasks

### Adding a New Service

1. Create new service in `apps/`:
```bash
cd apps
mkdir new-service
cd new-service
pnpm init
```

2. Update Terraform configuration:
```bash
cd infrastructure/modules/ecs
# Modify service definitions to include new service
```

3. Update CI/CD pipeline in `.github/workflows/`

### Database Migrations

```bash
# Run migrations
cd apps/api-service
pnpm migrate up

# Create new migration
pnpm migrate create my_migration
```

### Scaling Services

Modify `infrastructure/environments/dev/main.tf`:
```hcl
module "ecs" {
  source = "../../modules/ecs"
  
  service_config = {
    api_service = {
      desired_count = 3
      cpu          = 512
      memory       = 1024
    }
  }
}
```

## Troubleshooting

### Common Issues

1. Container Deployment Failures
```bash
# Check service status
aws ecs describe-services \
  --cluster main-cluster \
  --services api-service

# Check container logs
aws logs get-log-events \
  --log-group-name /dev/api-service \
  --log-stream-name <container-id>
```

2. Database Connection Issues
```bash
# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids <security-group-id>

# Test database connection
psql -h <rds-endpoint> -U postgres -d messages
```

### Getting Help

1. Check CloudWatch logs for errors
2. Verify Prometheus metrics
3. Check ECS service events
4. Review recent infrastructure changes in Terraform state

## Security

- All services run in private subnets
- RDS accessible only from service subnet
- Secrets managed through AWS Secrets Manager
- Regular security group audits recommended

## Contributing

1. Create feature branch
2. Make changes
3. Run tests: `pnpm test`
4. Submit PR

## License

MIT

Would you like me to expand on any section of this README?