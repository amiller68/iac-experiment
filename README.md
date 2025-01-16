# IAC Experiment

I'm trying to figure out the trade offs between strategies for developing and deploying
containerized services using fully bespoke IaC targeting AWS vs. a PaaS like Northflank.

This repo implements an exercise deploying a simple suite of containerized services and infrastructure following both strategies. We'll end up with the following components:

- a web service
- an api service
- a postgres database
- a serverless function that can run migrations

Check out the live versions of the services here:

- [aws](http://production-alb-2085663325.us-east-1.elb.amazonaws.com/)
- [northflank](https://p01--webservice--hzgwn22qv6ml.code.run/)

## what are we testing?

The goal is to arrive at a more rigourous understanding of what exactly you gain from using a PaaS like Northflank vs. a fully bespoke IaC strategy. We know the latter is going to be more work, see more complexity, and take more time to a PoC, but if we go with a PaaS, I wonder if we'll lose flexibility / auditability / etc. To fairly evaluate the tradeoffs, we're gonna define a shared set of requirements that should map on pretty well to either strategy, and evaluate:

- setup
- dsl
- structure
- level of effort
- control / flexibility / auditability
- developer experience for:
  - defining a new service
  - defining a new infra
  - developing features

With that in mind, here are the requirements. Our solution should:

- expose a web service and api service behind a shared domain name via a load balancer
  - web should be served at /
  - api should be served at /api
  - caveat: it's ok if we have different domain names during local development with docker compose
  - caveat: Northflank supports this when using custom domains, but otherwise we'll just use separate domain names
    for the web and api services
- utilize some managed abstraction on container orchestration
  - note: northflank fully manages k8s for you, we're not going to attempt to do that
    on AWS, and just opt for ECS Fargate
- host a postgres database
  - this should only be accessible from within the VPC by the
    - api service
    - and whatever functions / jobs we need to run migrations
- have a monitoring stack
  - note: for now this is not a priority in the context of AWS-IaC (taking too much time)
- implement some sane strategy for running migrations against the database
  - should be a job we can trigger from ci/cd in response to a new migration being merged into the repo
- not require any deployment step on the part of developers
  - deployments should be entirely handled by ci/cd

## project overview (code)

the project structure is a turbo monorepo structured as follows:

- apps
  - web-service
    - a simple express frontend service that hits the api service
  - api-service
    - a simple express backend service that hits the database
- packages
  - database
    - a lil js script for running migrations against the database
    - eventually this could utilize a full-fledged ORM + migrations tool like Prisma (yes I know)
    - it also contains a folder of migrations that we can run against the database
- northflank
  - a folder of northflank configuration files (just one for now)
- infrastructure
  - sum total of our terraform configuration against AWS
  - a folder of environment-specific configuration, for now just one for production

## a quick note on local development

I implemented a docker composition as a quick sanity check to make sure we can get the services running locally.
You can get that up and running right now with:

```bash
# Start all services
docker compose up -d
```

This will start up the following services:

- Web Service: http://localhost:3001
- API Service: http://localhost:3000
- PostgreSQL: localhost:5432
<!-- - Prometheus: http://localhost:9090
- Grafana: http://localhost:3002 (login should be admin/admin)

note: ignore the prometheus and grafana services for now, they ended up not being requirements for our AWS experiment (took too much time) -->

## AWS-IAC

### Setup

#### Prerequisites

- an aws account
- aws cli (setup with `aws configure` to some sort of admin)
- terraform

We're gonna walk through setting up the repository from scratch in order to deploy to AWS. You'll need to:
- setup a role for a github action to assume within your aws console.
  - this role should be attached to a policy that specidfies the necessary permissions for the github action to assume it. These are specified in `github-action-role.json`
- setup github as an OIDC provider for your aws account
- setup an environment for our github action to deploy to aws. the only support environment is `production` for now.
- setup a github action to deploy the infrastructure to aws by specifying the role you created above as `AWS_ROLE_ARN` in your github action environment secrets.
- created a `DATABASE_PASSWORD` secret in your github action environment secrets.
- created a `GRAFANA_PASSWORD` secret in your github action environment secrets. NOTE: we don't really need this right now.
- created an `ALERT_EMAIL` secret in your github action environment secrets.

### DSL

The AWS deployment surface is defined entirely in terraform.
Environment-specific configuration is defined in `infrastructure/environments/production` and variables are passed in via the github action environment secrets.

### Structure

We define the following modules in our terraform configuration:

- data
  - describes data sources and related resources:
    - postgres
    - lambda for running migrations
    - security groups
    - security / access relationships between resources
    - etc.
- ecs
  - describes the everything related to container orchestration:
    - cluster
    - services
    - task definitions
    - load balancers 
    - related security groups, policies, etc.
    - etc.
- monitoring
  - describes the monitoring stack
  - not implemented right now
- networking
  - describes the VPC and related resources
    - public / private subnets
    - route tables
    - vpc
    - etc.
- secrets
  - describes the secrets manager secrets
    - sets up a kms key for encrypting secrets
    - sets up a grafana admin password secret
    - sets up a db password secret
    - NOTE: i think there's probabaly a better way to set some of these up without passing them in as secrets.

### Level of Effort

### Control / Flexibility / Auditability

### Developer Experience


