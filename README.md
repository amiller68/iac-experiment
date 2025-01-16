# IAC Experiment

I'm trying to figure out the trade offs between strategies for developing and deploying
containerized services using fully bespoke IaC targeting AWS vs. a PaaS like Northflank.

This project is an exercise on deploying a simple suite of containerized services and infrastructure following both strategies. We'll end up with the following components:

- a web service
- an api service
- a postgres database
- a lambda function that can run migrations

Check out the live versions of the services here:

- [aws](http://production-alb-2085663325.us-east-1.elb.amazonaws.com/)
- [northflank](https://p01--webservice--hzgwn22qv6ml.code.run/)

## what are we testing?

The goal is to arrive at a more rigourous understanding of what exactly you gain from using a PaaS like Northflank vs. a fully bespoke IaC strategy. We know the latter is going to be more work / more complex more time to a PoC, but if we go with a PaaS, I wonder if we're gonna miss having more control / flexibility / auditability / etc. Therefore, we're gonna define a shared set of requirements that should map on pretty well to either strategy, and evaluate:

- how well each strategy meets the requirements
- how much work / time / complexity each strategy requires
- how much control / flexibility / auditability each strategy provides
- what the developer experience is like
- what the infrastructure experience is like
- etc.

With that in mind, here are the requirements. Our solution should:

- expose a web service and api service behind a shared domain name via a load balancer
  - web should be served at /
  - api should be served at /api
  - caveat: it's ok if we have different domain names during local development with docker compose
- utilize some managed abstraction on container orchestration
  - note: northflank fully manages k8s for you, we're not going to attempt to do that
    on AWS, and just opt for ECS Fargate
- host a postgres database
  - this should only be accessible from within the VPC by the
    - api service
    - and whatever functions / jobs we need to run migrations
- have a monitoring stack with prometheus and grafana
  - note: for now this is not a priority in the context of AWS-IaC (taking too much time)
- implement some sane strategy for running migrations against the database
  - should be a job we can trigger from ci/cd in response to a new migration being merged into the repo
- not require any deployment step on the part of developers
  - deployments should be entirely handled by ci/cd

Explicit non-requirements:

- TLS termination
- any kind of authentication

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
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3002 (login should be admin/admin)

note: ignore the prometheus and grafana services for now, they ended up not being requirements for our AWS experiment (took too much time)

## AWS-IAC

- ./infrastructure defines the sum total of the infrastructure and services we're going to deploy to AWS
- ./infrastructure/environments/production is the configuration for the production environment (it's the only environment for now)

### Setup

TODO: the rest of this

