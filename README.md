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

## a note on my background and motivation

I'm a very DIY oriented engineer, but I am by no means an expert in DevOps at scale. I have never maintained the AWS posture I will be laying out here in production. I have never used Northflank (or any other PaaS, maybe except for shuttle-rs) prior to this experiment. Feel free to build off the work here, but also you should audit it for yourself and make sure you understand it before using it in production.

I would love to hear your thoughts if you do have the time and experience to do so. Specifically I'm mostly wondering about:
- what am I missing? are there any obvious pain points I'm not considering?

## what are we testing?

The goal is to arrive at a more rigourous understanding of what exactly you gain from using a PaaS like Northflank vs. a fully bespoke IaC strategy. We know the latter is going to be more work (at least upfront) and entail more complexity, but if we go with a PaaS, I wonder if we'll lose non-trivial amount of flexibility / auditability / etc. To fairly evaluate the tradeoffs, we're gonna define a shared set of requirements that should map on pretty well to either strategy, and evaluate:

- setup: what do we need to do before we can deploy our services in a fresh environment and be able to ship features with ci/cd?
- IaC: how easy is it to define our services and infrastructure using the provided DSL (or equivalent)?
- structure: what does our infrastructure posture end up looking like (and what exactly do we need to define to implement it)?
- maintainability: how much work is it to maintain our infrastructure? we want to reason about both the upfront work and the expected cadence of work to maintain workflows, define new services, and provision new infrastructure.

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
    - note: possible, but not implemented in our Northflank experiment
- implement some sane strategy for running migrations against the database
  - should be a job we can trigger from ci/cd in response to a new migration being merged into the repo
- not require any deployment step on the part of developers
  - so long as changes are confined to defined services and / or migrations, developers should be able to deploy code changes by pushing to the repo

with that in mind, let's dive into the code.

## project overview (code)

the project structure is a turbo monorepo structured as follows:

- src
  - services
    - web-service
      - a simple express frontend service that hits the api service
    - api-service
    - a simple express backend service that hits the database
  - packages
    - database
      - a lil js script for running migrations against the database
      - eventually this could utilize a full-fledged ORM + migrations tool like Prisma (yes I know)
      - it also contains a folder of migrations that we can run against the database
- iac
  - northflank
    - a folder of northflank template files (just one for now)
  - aws
    - sum total of our terraform configuration against AWS, we'll discuss this in more detail below
    - a folder of environment-specific configuration, 
      - for now we just have one for production

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

with the required database accessible within the docker composition.

## AWS-IAC

### Setup

Before you begin, you'll need:

- an aws account
- the aws cli (setup with `aws configure` to some sort of admin)
- terraform cli
- and this repo forked into your own github account

We're gonna walk through setting up the repository from scratch in order to deploy to AWS. You'll need to:
- setup a github as an OIDC provider for your aws account to connect your github action to aws.
- create a role for a github action to assume within your aws console. your role should allow github actions to assume it as a temporary web identity when invoked by a github action from within your repo.
- create a policy to attach to your role that allows it to make the necessary aws calls to deploy the infrastructure. this should just contain the permissions described in `github-action-role.json`.
- create an s3 bucket and dynamodb table to store terraform state. place these in the same region as where you're deploying your infrastructure. if you want these to work in our `production` environment with no further configuration, you should name the bucket `iac-experiment-tf-state` and the table `terraform-state-lock`.
- setup an environment for our github action to deploy to aws. the only environment we support is `production` for now.
- create a secret in your new `production` environment called `AWS_ROLE_ARN` and set it to the arn of the role you created above. This will allow the github action to assume the correct role when it is invoked.
<!-- - create a secret in your new `production` environment called `DATABASE_PASSWORD` and set it to the password you want to use for your database. make sure this is a sufficiently random password. -->
- created a variable in your new `production` environment called `ALERT_EMAIL` and set it to the email you want to use for recieving infrastructure alerts.

NOTE: apologies if this instructions are not more specific, but I'm not exactly trying to write a tutorial so much as evaluate complexity. You're favorite LLM should have no problem helping you out here. the full process should not take more than 10 minutes.

<!-- NOTE: notice that create secrets ourselves here, and inject them as variables into the terraform configuration. this is a bit of a pain, and we could get around this by relying enitrely on the secrets manager to manage our secrets. Another option would be to allow an environment manager like `infisical` to manage our secrets and inject them into the terraform configuration when we run our github action. -->

### IaC

The AWS deployment surface is defined entirely in terraform's DSL, HCL.

Environment-specific configuration is defined in `iac/aws/environments` and any additional secrets are passed in via the github action environment secrets.

If you are comfortable with terraform, you should be easily able to understand the structure of the terraform configuration and how it maps onto the requirements.

### Structure

At a high level we end up with the following infrastructure:

- a vpc with public and private subnets
- our api service and web service running in ecs fargate behind a load balancer
- a postgres database running in a private subnet
- a lambda function for running migrations against the database
- a secrets manager secret for the database password
- and a bunch of networking and security rules to make everything work together securely

On a more granular level, our AWS infrastructure is organized into several key terraform modules, each handling a specific concern:

- [data](/iac/aws/modules/data/main.tf)
  - manages our data layer including:
    - RDS postgres instance in private subnet
    - lambda function for running migrations + build process for the lambda function. also briefly houses the lambda function code to build the deployed artifact.
    - security groups controlling database access:
      - allows access from the api service
      - allows access from the lambda function
    - IAM roles and policies for database access
    - various connections to the VPC and other resources

- [ecs](/iac/aws/modules/ecs/main.tf)
  - handles container orchestration including:
    - ECR repositories for the images we build of our services
      - this can probably be its own module
    - a single ECS Fargate cluster
    - application load balancer with an 
      -  appropriate security group, which allows access over HTTP/HTTPS
      - target groups for hitting the api and web services. this groups both services behind the same load balancer / domain name and lets us define health checks for each service for determining which service to route traffic to.
      - listener rules for routing traffic to the appropriate target group based on the url path
    - service definitions and task configurations, including:
      - task exectuion roles and policies
      - ecs task definitions, including:
        - environment variables
        - secrets
        - port mappings
        - logging configuration
        - cpu and memory requirements
        - health check configuration
      - the ecs services themselves, which run the tasks and allow us to control:
        - cluster
        - launch type
        - network configuration
        - desired count
      - NOTE: we don't employ any auto-scaling policies here, but we could easily add them in the future.

- [networking](/iac/aws/modules/networking/main.tf)
  - defines our network topology:
    - VPC with public/private subnets
    - internet and NAT gateways
    - route tables
    - network security groups
    - vpc endpoints for secrets manager, rds, and sns
      - this ensures that our internal aws services can communicate with each other without going through the public internet, which is helpful for compliance, security, and performance.
    - eip for exposing our services to the internet

- [secrets](/iac/aws/modules/secrets/main.tf)
  - handles secrets management:
    - KMS keys for encryption
    - secrets manager secrets
    - IAM policies for secret access
    - really only creates and manages the database password for now, but could be extended to manage other secrets in the future.

Each module is designed to be self-contained but able to integrate with others through clearly defined interfaces (security groups, IAM roles, etc). This modularity makes it easier to understand and maintain individual components while ensuring they work together as a cohesive system.

### Maintainability

In terms of maintainability, let's look at the following:

- how much work did it take to get to a working state?
  - NOTE: i tried writing our AWS-IAC approach prior to the Northflank experiment, so initial code base / packages / local dev setup are subsumed by the timeframes included in my evaluation here.
  - time
    - it took me about 1 engineering day to setup the repo, aws account, initial terraform state, and get the infrastructure deployed. it took about half an engineering day to debug some deployment issues and simplify the ci/cd workflow. it took about another half an engineering day (while writing this README) to evaluate the structure, audit my work, and cleanup unused resources (yes there was even more terraform code in the repo than what's included here).
  - effort
    - i've written terraform before, so I was already familiar with its core syntax and concepts. this time around i was able to both leverage that knowledge and utilize cursor to rapidly prototype and iterate on the infrastructure. i won't say that cursor was the perfect partner in this, as it did stuff like:
      - hallucinate requirements for services
      - occasionally made up variables and configurations that didn't exist
    
    - however, this was mostly true when trying to get it to write ALOT of functionality all at once. i often ran into issues on my first engineering day when trying to get a bunch of stuff working at once. while auditing my work, cursor was a big help in:
      - reasoning about the interrelationships between modules and resources
        - example: 
          - q: 'why do we need health checks on both our load balancer target groups and our ecs task definitions?'
          - a: 'the health checks are used to determine which service to route traffic to. the load balancer health checks are used to determine if the service is healthy and should receive traffic, while the ecs task health checks are used to determine if the service is healthy and should continue to receive traffic, or otherwise be replaced by a new task.'
      - making incremental, well-motivated changes to the codebase
  - conclusion
    - i'd clock the total time investment for a similar project at about 2-3 engineering days if starting from scratch with the level of experience i have coming into the project + with similar LLM assistance. 
    - Claude is apparently very well versed at both terraform and the inner workings of aws (which makes sense since there's a lot of example code out there), so it's probably possible to get this down to 1-2 engineering days with a bit more effort + more targetted requests.
- what does the auditing process look like?
  - HCL has its quirks, but just keep the following in mind:
    - all state can (and should / is) be managed by terraform within a bucket and some sort of shared lock. when on AWS this is S3 and DynamoDB.
    - anything specific to an environment can be managed essentially as its own `main.tf` file with state pulled locally and persisted to the bucket.
    - you can compose groups of resources together a module, and include modules within other modules.
    - terraform handles state management for you, so you can just focus on defining your resources using your environment and modules, and terraform will handle the rest.
  - auditing terraform looks and feels alot like auditing code
    - start in your main environment, and see what modules you're sourcing, and what arguments you're passing to them
    - audit each module for any resources it's creating and how it's interacting with other modules
  - gauging interdependencies can get kinda crazy, but keep the following in mind:
    - variables and outputs are all explicit, and basically no resource or environment is ever accessible to another without being explicitly defined as an input.
    - terraform manages state for you, and part of that is resolving interdependencies.
  - that being said, you still need to know what you're doing.
    - you must reason about the security requirements of your application and know how to judge your HCL code accordingly.
    - you must be confident in your ability to implement RBAC and other security policies for your team or organization.
    - we haven't even touched on observability, monitoring, alerting, etc. ideally in addition to auditing yur HCL, you should have an understanding of what you're trying to get your infrastructure to do and gauge how well provisiioned it is.
  - conclusion
    - auditing for strict correctness is very doable by just relying on the terraform cli and AWS console.
    - auditing for compliance and security is doable but should be coupled with a good understanding of best practices.
    - auditing for performance and infrastructure requires independent solutions and domain expertise in observability and monitoring.
- what does making an infrastructure change look like?
  - this is where terraform really shines.
  - adding, modifying, or removing resources is as simple as editing the HCL file and running `terraform apply`.
  - you can also use `terraform plan` to see what terraform is going to do before applying your changes and make sure you're on the right track.
  - you can either edit the HCL files directly or use a tool like cursor to make changes to your infrastructure using well-motivated requests:
    - example (not a real one):
      - q: 'hey i'd like to add a bucket to my infrastructure. this should be accessible only by the api service within our vpc'
      - a: 'great, i'll add a bucket to the data module and make sure it's only accessible by the api service...'
  - infrastructure changes are uniformally deployed within a git workflow.
    - you can protect access to infrastructure changes by using a combination of branch protection rules and required status checks.
    - you can thoroughly audit and review changes before merging them into your environment.
  - that being said, some infrastructure changes are going to be more complex than others.
    - creating a bucket is as easy as adding the resource, defining a connection to a VPC, and adding a policy to allow access from the api service.
    - creating a new service in ECS might entail more work, such as:
      - creating a new target group
      - creating a new listener rule
      - creating a new task definition
      - creating a new service
      - creating a new security group
  - conclusion
    - being able to declaritivly define and plan infrastructure changes is very powerful, but it's not always easy to do so.
    - still requires a good understanding of the infrastructure and how it's composed.
      - this is well enabled by an LLM, but you should also be able to reason about the infrastructure and how it's composed yourself.
    - should still include oversight and review for complex changes.
- what exactly do we need to keep maintaining in the long run?
  - as awlays, you'll need to do regualr security audits of your dependencies and builds (this is just part of being a software developer)
  - NOTE: you'd also need to make sure you're github action policy is up to date with the latest permissions you need to deploy your infrastructure. You can either update this manually OR if you have an admin account configred on your local machine, you can run `./bin/update-github-action-policy.sh` to update it.
  - Notably with the example implemented here, we don't need to manage anything like k8s ourselves, rolling out kernel patches, etc.
  - we do need to reason about the security of our infrastructure and how to keep it secure:
    - making sure database is secure and running a secure version of postgres
    - remaining vigilant about security best practices and keeping permissions up to date and minimized
  - we also need to to keep monitoring performance and ensuring:
    - our services are healthy and responsive
    - utilize the correct amount of compute and memory for our services
    - have appropriate auto-scaling policies in place (if required)

### Notes

- there are external tools and platforms for managing terraform outside of just the cli + AWS. we have not evaluated how such tools might alleviate pain points apparent here.

## Northflank

read this entire section with the giant grain of salt that i've never used northflank before, and i might not be missing or paying attention to important features, products, or functionality that might alleviate some of the pain points i'm describing here.

### Setup

Before you begin, you'll need:

- a northflank account
- and this repo forked into your own github account

In order to deploy to northflank starting from scratch, you'll need to:
- configure a github oauth app for northflank to use to authenticate your github. you must give this read and write access to the repository.
- create a new template in northflank. enable git-ops and connect it to your github repository on the `main` branch and set the template to `iac/northflank/template.json`. press the `fetch` button to verify that the template is valid.
- enable concurrency control for your template, and save the template. this should commit an update (not like we're changing anything) to repo, and start deploying a build.
- NOTE: this workflow will create a project called `iac-experiment` in northflank. if you'd like to change this, you may by editing the workflow and changing the project name.

Northflank should begin to:
- build your api and web services, as well as migration job as containers
- provision a postgres database
- set up a shared secret group that exposes your postgres URI to the rest of your services and jobs
- run migrations against the database as a manual job
- deploy the api service exposed to the internet under a random and persistent domain name
- deploy the web service exposed to the internet under a random and persistent domain name (this should look logically related to the api servic)

### IaC

Northflank provides its own DSL for defining infrastructure on their platform. 
It allows us to:
- define workflows that provision infrastructure and deploy services and jobs
- pass in arguments at runtime that modify the behavior of the workflow, similar to terraform variables

I didn't try this but you could use this to define different environments in much the same way you would with terraform (just might require a bit more hacking).

The DSL itself is pretty simple, if maybe not a little hard to get used to. the template i generated using their web UI is described in a single [json file](/iac/northflank/template.json). Instead of being able to explicitly distinct define inputs and outputs, relations between modules, and organize components however I see fit, our templates play out a single workflow that sets up builds, provisions infrastructure, and deployed jobs and services.

On that note, I found myself not even really trying to use the DSL at all, and instead relied almost entirely on the UI to set up my infrastructure. There are a couple of reasons I think this is the case:
- I don't know the DSL well enough to be productive with it yet
- the DSL is not as well documented as terraform's DSL for AWS. Rather than relying on an LLM to help me understand the DSL, I found it easier to just stick to the padded walls of the UI.
- looking at one big json file and not being able to compose my infrastructure into modules made me feel a bit disorganized.
- the DSL is not declarative, so I couldn't easily test and plan my infrastructure changes prior to committing them to the repo.

### Structure

At a high level, we end up with the following infrastructure:

- a vpc (i think) to host our services and jobs and addons
- a postgres database
- a shared secret group that exposes your postgres URI to the rest of your services and jobs
- a migration job that runs migrations against the database
- an api service exposed to the internet
- and a web service exposed to the internet

Behind the scenes Northflank is provisioning and managing k8s for us, and we just get to deploy our services to it without setting up things like:
- security groups
- load balancers
- task definitions
- etc

Our workflow orchestrates the following:
- creates a project in which to deploy our infrastructure
- defines a parallel workflow that:
  - builds our api and web services as containers, as well as a migration job
- provisions a postgres database
- creates a shared secret group that exposes your postgres URI to the rest of your services and jobs
- creates a migration job that runs our migrations container as a job
- creates an api service exposed to the internet
- creates a web service exposed to the internet

### Maintainability

- how much work did it take to get to a working state?
  - time
    - setting up a simple deployment with no IaC and where i manually ran migrations took about 1-2 hours.
    - setting up a simple template in the northflank web UI with migrations run as a job took about 4-6 hours of trial and error.
    - i messed around with pipelines and the DSL for another hour or so, but lets just call that a wash and ignore it.
  - effort
    - i didn't have to write a single line of DSL or git workflow code.
    - i spent a lot of time reading docs and trying to figure out best practices for using Northflank.
    - it doesn't seem like there are a ton of different ways to do or organize projects and workflows in Northflank, which definitely removed some cognitive overhead.
  - conclusion
    - i'd clock the total time investment for a similar project at an engineering day or less in order to get a simple, single environment deployment working starting from scratch.
    - i'm certain there are features in which i am not accounting for that possibly would've made things easier / allowed me to be more expressive.
- what does the auditing process look like?
  - NOTE: preface this by saying maybe i just have skill issues
  - non declarative IaC is hard to audit
    - as far as i know, there's no equivalent to terraform's `terraform plan` that will tell you what northflank is going to do before you commit your changes.
    - the order in which you define resources in your workflow is important, as norhtflank doesn't create a graph structure that defines the interdependencies between resources.
    - you can use references to resources in your workflow, but you must do so in a logical order:
      - example: it wasn't intuitive to me that if i wanted to use my api service's url as an environment variable for my web service, i couldn't just reference the api service's url in the web service's environment variables section. i had to first define the deployment of my api service, and then reference it in the web service's environment variables section.
    - references to environment variables are not necessarily explicit, so you kinda need to remember what you've already defined
      - example: consider the following section of the workflow:
        ```json
        {
                "kind": "SecretGroup",
                "spec": {
                  "type": "secret",
                  "secretType": "environment-arguments",
                  "priority": 10,
                  "secrets": {
                    "variables": {},
                    "files": {}
                  },
                  "addonDependencies": [
                    {
                      "addonId": "${refs.postgres.id}",
                      "keys": [
                        {
                          "keyName": "POSTGRES_URI",
                          "aliases": [
                            "DB_URI"
                          ]
                        }
                      ]
                    }
                  ],
                  "name": "SecretGroup",
                  "restrictions": {
                    "restricted": false,
                    "nfObjects": [],
                    "tags": []
                  },
                  "projectId": "${refs.iac-experiment.id}"
                },
                "ref": "secretgroup"
              },
        ```
        
        Here we're declaring a secret group that references the `postgres` addon, and creates an environment variable `DB_URI` that is set to the postgres URI.
        Any service or job (that comes after the secret group in the workflow) may reference that environment variable.

        This is probably not a big deal, but in my opinion it makes it kinda of hard to evaluate whether or not when we define our api service deployment later in the workflow, we have access to the `DB_URI` environment variable:

        ```json
              {
                "kind": "DeploymentService",
                "spec": {
                  "deployment": {
                    "instances": 1,
                    "storage": {
                      "ephemeralStorage": {
                        "storageSize": 1024
                      },
                      "shmSize": 64
                    },
                    "docker": {
                      "configType": "default"
                    },
                    "internal": {
                      "id": "${refs.iac-experiment-api-service-builder.id}",
                      "branch": "main",
                      "buildSHA": "latest"
                    }
                  },
                  "runtimeEnvironment": {},
                  "runtimeFiles": {},
                  "billing": {
                    "deploymentPlan": "nf-compute-10"
                  },
                  "name": "iac-experiment-api-service-deploy",
                  "ports": [
                    {
                      "internalPort": 3000,
                      "public": true,
                      "protocol": "HTTP",
                      "name": "p01",
                      "domains": [],
                      "security": {
                        "sso": {},
                        "policies": [],
                        "credentials": [],
                        "verificationMode": "or"
                      },
                      "disableNfDomain": false
                    }
                  ]
                },
                "ref": "iac-experiment-api-service-deploy"
              },
        ```
        My intuition looking at this (and this issue is replicated in the web UI) is that this container would not have access to the `DB_URI` environment variable, as it's defined after the secret group. Yet, in fact, it does.

        I spent a solid half hour / hour combing through the docs trying to understand this relationship before I just deployed the workflow and saw that it worked.
  - BUT once you learn the quirks of how northflank works, it's pretty easy to see both the status of your workflow and the state of your infrastructure in the UI:
    - you can play around with you're template in a kinda WYSIWYG way by dragging and dropping resources into your workflow
    - everything is nicely organized by projects, so you're only ever a few clicks away from observing logs, metrics, and other resources
  - conclusion
    - non declarative IaC is a big pain point
    - this is somewhat mitigated by having a nice UI
- what does making an infrastructure change look like?
  - NOTE: there are probably neat things that you can script for pipelines and releases, but i didn't figure out how those work
  - updating the template either in the UI or in the repository triggers a new build of your infrastructure
  - i can't really speak or otherwise evaluate a process surrounding editing the DSL directly within the repository:
    - i didn't have success using it
    - the DSL seems difficient in comparison to terraform's
    - LLMs are not going to be nearly as helpful as they are with terraform, as the DSL is not as well documented nor are there as many examples using it
  - in theory, small changes such as updating arguments or reconfiguring a service would be easy to do in the DSL, and this could fit into a propper git workflow as part of a PR
  - however you won't get the same level of feedback as you would running `terraform plan`
  - conclusion
    - you're probably going to end up clicking around the UI to make changes to your infrastructure
    - but you certainly can make changes to the DSL directly within the repository similar to how you would with terraform
- what exactly do we need to keep maintaining in the long run?
  - as awlays, you'll need to do regualr security audits of your dependencies and builds (this is just part of being a software developer)
  - we don't really need to reason about add-on security patches, as northflank will handle that for us
  - we don't really need to reason about RBAC, as northflank will handle that for us
  - we don't really need to put effort into setting up observability, as northflank will handle that for us
  - we just have to reason about compute and memory for our services and jobs and sensible policies for scaling

### Notes

- i'm sure that a [pipeline](https://northflank.com/docs/v1/application/release/create-a-pipeline-and-release-flow#automatically-run-a-release-flow) could have been useful in orchestrating / defining our workflow, especially against different environments, but for the life of me i couldn't figure out how to get it to work.

- it seems like the web ui is somewhat difficient in comparison to the very expansive API and CLI that the northflank team has built out.

## Conclusion

i think it makes sense to start by comparing our two strategies along the same axes we evaluated them on:

- setup
  - this is an easy win for northflank, the time to a PoC single environment deployment is about 1 engineering day or less, as compared to 2-3 engineering days for terraform.
- iac
  - terraform is a clear winner here, as it's a declarative language that allows you to plan and preview your infrastructure changes before committing them to the repo.
  - northflank is not declarative, so you can't really plan your infrastructure changes before committing them to the repo.
- structure
  - there's not a clear winner here
  - terraform allows you to compose your infrastructure into modules and manage state in a single bucket. it allows for high levels of expressivity and customization.
  - that expressivity has a price, as terraform is orders of magnitude more complex than northflank's DSL. we had to set up VPCs, security groups, IAM roles, etc. This is not an undertaking for the faint of heart OR anyone who hasn't already cut their teeth on AWS.
  - our terraform codebase clocks in at almost 1400 lines of HCL
  - northflank cuts out a lot of unneccesary complexity setting up networking, security groups, etc.
  - our northflank template clocks in at about 400 lines of JSON
    - (honestly that seems kinda verbose for what we actually customize in our infrastructure)
- maintainability
  - AWS-IaC can be a bit of a beast, and, if not a full time dev ops engineer, you're probably going someone on your team to own it.
  - northflank is a bit easier to maintain, as it's a bit more opinionated and doesn't require as much setup. devs can just focus on writing code and not worry about the underlying infrastructure.
  - with AWS-IaC, you're going to need to have a good understanding of the infrastructure and how it's composed. but having that will enable you a lot more flexibility and customization if that's what you need. If you're after specific aws resources as well (such as SES, cloudfront, etc) then not having to manage that through a northflank integration might be a solid reason to go with terraform.
  - northflank is more restrictive, but will probably meet 80% of your needs out of the box without much work or wrangling. you might have to do a bit more work reading docs and figuring out how to do things if you're already familiar with aws and setting up your own deployments.

## other notes / considerations

- we're not at all testing how to manage multiple environments or deploy pipelines here! both are enitrely possible with both strategies, but we have not evaluated how big of a pain it is to do so.

- my motivation in expoloring both of these strategies is very conciously oriented towards scale and access to specific aws / northflank resources. you should dismiss both of these solutions out of hand if either:
  - scaling
  - or access to specific aws / northflank resources

  are not *well motivated, sensible, or otherwise necessary* requirements for your project. at best, go setup a persistent ec2 and a docker composition and call it a day. i'm a big advocate of [kamal](https://kamal-deploy.org/) for just this reason.
 


