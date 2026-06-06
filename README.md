# DevOps Assignment — Octa Byte AI

A fully automated DevOps pipeline deploying a containerised Flask application on AWS, with infrastructure-as-code, CI/CD, and centralised monitoring.

---

## Architecture Overview

```
Internet
   │
   ▼
Application Load Balancer (public subnets, port 80)
   │
   ▼
EC2 Instance — Flask app in Docker (public subnet, port 5000)
   │
   ▼
RDS PostgreSQL (private subnets, port 5432)
```

| Layer | Technology |
|---|---|
| Infrastructure | Terraform 0.12, AWS VPC / EC2 / RDS / ALB |
| Application | Python Flask, PostgreSQL (psycopg2), Gunicorn |
| Containerisation | Docker (multi-stage build, non-root user) |
| CI/CD | GitHub Actions (test → scan → build → deploy) |
| Registry | DockerHub |
| Monitoring | AWS CloudWatch (agent + custom metrics + dashboards) |

---

## Part 1 — Infrastructure (Terraform)

### Resources provisioned

- **VPC** — `10.0.0.0/16` with 2 public and 2 private subnets across 2 AZs
- **Internet Gateway** — attached to the VPC for public subnet egress
- **Security Groups**
  - ALB: inbound 80/443 from internet
  - App (EC2): inbound app port from ALB only, SSH from internet (for CI/CD deployments)
  - RDS: inbound 5432 from App SG only
- **EC2** — Amazon Linux 2, public subnet, public IP, Docker + CloudWatch agent installed via user-data
- **RDS PostgreSQL 15** — private subnets, encrypted, not publicly accessible
- **ALB** — public subnets, HTTP listener → target group on port 5000, health check at `/health`
- **CloudWatch** — log groups, IAM role/instance profile, two dashboards

### Directory structure

```
terraform/
├── provider.tf        # AWS provider
├── backend.tf         # Local state backend
├── variables.tf       # All input variables
├── locals.tf          # Common tags
├── vpc.tf             # VPC, subnets, IGW, route tables
├── security_groups.tf # ALB / App / RDS security groups
├── ec2.tf             # EC2 instance, key pair, IAM profile
├── rds.tf             # RDS PostgreSQL, subnet group
├── alb.tf             # ALB, target group, listener
├── cloudwatch.tf      # Log groups, IAM role, dashboards
└── outputs.tf         # ALB DNS, EC2 IP, RDS endpoint
```

### Deploy infrastructure

```bash
cd terraform

terraform init

terraform plan \
  -var='db_password=YOUR_DB_PASSWORD' \
  -var='public_key=YOUR_SSH_PUBLIC_KEY'

terraform apply \
  -var='db_password=YOUR_DB_PASSWORD' \
  -var='public_key=YOUR_SSH_PUBLIC_KEY'
```

### Tear down

```bash
terraform destroy \
  -var='db_password=YOUR_DB_PASSWORD' \
  -var='public_key=YOUR_SSH_PUBLIC_KEY'
```

### IAM — minimum privilege policy

`iam/terraform_policy.json` contains a custom IAM policy for the Terraform deployment role covering only the actions required:

| Statement | Permissions |
|---|---|
| EC2NetworkingAndVPC | VPC, subnets, IGW, route tables, security groups |
| EC2InstancesAndEIP | Run/stop/terminate instances, key pairs, EIP |
| ElasticLoadBalancing | ALB, target groups, listeners |
| RDS | DB instances, subnet groups, parameter groups |
| IAMForEC2Role | Create/attach role and instance profile for CloudWatch |
| CloudWatchAndLogs | Dashboards, metrics, log groups |

To create or update the policy on AWS:

```bash
# Create
aws iam create-policy \
  --policy-name TerraformDeployPolicy \
  --policy-document file://iam/terraform_policy.json

# Update (replace VERSION_ID with the old version)
aws iam create-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/TerraformDeployPolicy \
  --policy-document file://iam/terraform_policy.json \
  --set-as-default

aws iam delete-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/TerraformDeployPolicy \
  --version-id VERSION_ID
```

---

## Part 2 — Application & CI/CD Pipeline

### Application

A Flask API with a user management UI backed by RDS PostgreSQL.

```
app/
├── app.py             # Flask routes + CloudWatch metrics middleware
├── requirements.txt   # Dependencies
├── Dockerfile         # Multi-stage build, non-root user
├── conftest.py        # pytest path fix
├── templates/
│   └── index.html     # User management UI
└── tests/
    └── test_app.py    # Unit tests (9 tests, DB and boto3 mocked)
```

**Endpoints:**

| Method | Path | Description |
|---|---|---|
| GET | `/` | User management UI |
| GET | `/health` | Health check (used by ALB) |
| GET | `/db` | Database connectivity check |
| GET | `/users` | List all users |
| POST | `/users` | Create a user `{"name": "...", "email": "..."}` |

### Run locally (without Docker)

```bash
cd app
pip install -r requirements.txt

export DB_HOST=localhost DB_NAME=appdb DB_USER=dbadmin DB_PASSWORD=secret
python app.py
```

### Run locally with Docker

```bash
cd app
docker build -t devops-app .
docker run -p 5000:5000 \
  -e DB_HOST=host.docker.internal \
  -e DB_NAME=appdb \
  -e DB_USER=dbadmin \
  -e DB_PASSWORD=secret \
  -e AWS_REGION=us-east-1 \
  devops-app
```

### Run tests

```bash
cd app
pip install pytest pytest-cov
pytest tests/ -v --cov=app --cov-report=term-missing
```

### CI/CD Pipeline

`.github/workflows/pipeline.yml` — triggered on every push to `main` and on pull requests.

```
push to main
     │
     ├─ test               Run unit tests + coverage
     │
     ├─ scan               pip-audit (dependency CVEs) + Trivy (container CVEs)
     │
     ├─ build              Build Docker image → push to DockerHub
     │
     ├─ deploy-staging     SSH to EC2 → pull image → restart container
     │                      └─ Slack notification (success or failure)
     │
     └─ deploy-production  Requires manual approval in GitHub Environments
                            └─ Slack notification (success or failure)
```

To enable the manual approval gate for production:
1. Go to **GitHub repo → Settings → Environments → New environment** → name it `production`
2. Enable **Required reviewers** and add yourself
3. Every pipeline run will pause before production and wait for your approval

### GitHub Secrets required

| Secret | Description |
|---|---|
| `DOCKERHUB_USERNAME` | DockerHub username |
| `DOCKERHUB_TOKEN` | DockerHub access token |
| `EC2_HOST` | Staging EC2 public DNS / IP |
| `EC2_USER` | SSH username (`ec2-user`) |
| `EC2_SSH_KEY` | Private SSH key (contents of `~/.ssh/id_ed25519`) |
| `DB_HOST` | Staging RDS endpoint (from `terraform output rds_endpoint`) |
| `DB_NAME` | Database name (default: `appdb`) |
| `DB_USER` | Database username (default: `dbadmin`) |
| `DB_PASSWORD` | Staging database password |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL |
| `PROD_EC2_HOST` | Production EC2 public DNS / IP |
| `PROD_DB_HOST` | Production RDS endpoint |
| `PROD_DB_PASSWORD` | Production database password |

---

## Part 3 — Monitoring & Logging

### CloudWatch Log Groups

| Log Group | Source | Retention |
|---|---|---|
| `/{project}/app` | `/var/log/app.log` on EC2 | 30 days |
| `/{project}/system` | `/var/log/messages` on EC2 | 30 days |
| `/{project}/access` | `/var/log/nginx/access.log` on EC2 | 30 days |

### Custom Application Metrics

The Flask app emits custom metrics to CloudWatch via boto3 on every request (namespace: `devops-assignment/App`):

| Metric | Unit | Description |
|---|---|---|
| `RequestCount` | Count | Total requests (per endpoint + aggregate) |
| `ErrorCount` | Count | 4xx + 5xx responses |
| `Latency` | Milliseconds | End-to-end response time |

### Dashboards

#### Infrastructure Dashboard (`devops-assignment-infrastructure`)

![Infrastructure Dashboard](docs/screenshots/devops-assignment-infrastructure.png)

Monitors EC2 and RDS health:
- EC2 CPU Utilization
- EC2 Memory Usage % (via CloudWatch agent)
- EC2 Disk Usage % (via CloudWatch agent)
- RDS CPU Utilization
- RDS Database Connections
- RDS Free Storage

#### Application Dashboard (`devops-assignment-application`)

![Application Dashboard](docs/screenshots/devops-assignment-application.png)

Monitors app and ALB performance:
- Request Count (custom metric from Flask middleware)
- Error Count — 4xx + 5xx (custom metric)
- Average Latency in ms (custom metric)
- ALB Request Count
- ALB 5xx Errors
- ALB Target Response Time

---

## Best Practices

### Secret Management

- No secrets are hardcoded anywhere in the codebase
- All sensitive values (DB password, SSH key, DockerHub token) are stored as GitHub Actions secrets
- Terraform variables `db_password` and `public_key` are passed at runtime via `-var` flags, never stored in `.tf` files or committed
- The `.gitignore` excludes `*.tfvars`, `terraform.tfstate`, and `.terraform/`

### IAM Least Privilege

- Terraform runs under a dedicated `TerraformRole` with a custom minimum-privilege policy (`iam/terraform_policy.json`)
- The EC2 instance has its own dedicated IAM role (`devops-assignment-ec2-cloudwatch-role`) with only `CloudWatchAgentServerPolicy` — no broad permissions
- RDS is in private subnets and is not publicly accessible

### Container Security

- Multi-stage Docker build — build tools are not present in the final image
- App runs as a non-root user (`appuser`)
- Container image is scanned on every CI run with Trivy (HIGH/CRITICAL severity)
- Dependencies are scanned with pip-audit on every CI run

### RDS Backup & Recovery

- RDS automated backups are enabled (AWS default: 7-day retention)
- RDS storage encryption is enabled (`storage_encrypted = true`)
- RDS is in private subnets — not reachable from the internet
- Multi-AZ can be enabled by setting `db_multi_az = true` in variables

### Network Security

- EC2 is only reachable on port 5000 from the ALB security group
- RDS is only reachable on port 5432 from the EC2 security group
- All user traffic enters through the ALB (single entry point)

### Cost Optimization

- **Single EC2 instance** — one `t3.micro` instead of an auto-scaling group; right-sized for the workload
- **NAT Gateway removed** — EC2 is in a public subnet with a public IP, eliminating the ~$32/month NAT Gateway cost. RDS in the private subnet does not need internet access
- **RDS `db.t3.micro`** — smallest instance class sufficient for the assignment workload
- **20 GB gp2 storage** — minimum required; gp3 would be cheaper at scale
- **No Multi-AZ for RDS** — disabled (`db_multi_az = false`) to avoid doubling RDS cost in a non-production environment; can be enabled via variable
- **CloudWatch log retention set to 30 days** — avoids indefinite log storage accumulation
- **Local Terraform backend** — avoids S3 + DynamoDB costs for state storage in a lab environment

---

## Approach

### Infrastructure-first

The project was built bottom-up: VPC and networking first, then compute (EC2), then database (RDS), then the load balancer, and finally monitoring. This order ensures each layer is tested before the next depends on it.

### Terraform 0.12 compatibility

The lab server runs Terraform 0.12.29. Several syntax differences from Terraform 1.x required adjustments:
- Removed `required_providers` block with `source` attribute (not supported in 0.12)
- Removed `sensitive = true` on variables (added in 0.14)
- Used `vpc = true` instead of `domain = "vpc"` on EIP resources (old AWS provider attribute name)
- Used `name` instead of `db_name` on `aws_db_instance` (old provider attribute)

### Local Terraform backend

The lab IAM role did not have S3 permissions, so the Terraform state is stored locally on the lab server (`terraform.tfstate`). In production this would use an S3 backend with DynamoDB locking.

### Single EC2 in public subnet

Originally the design had EC2 in a private subnet with a NAT Gateway, but the lab environment's IAM restrictions and cost considerations led to moving EC2 to the public subnet. RDS remains in private subnets with no internet access.

### Custom CloudWatch metrics

Rather than relying solely on ALB metrics, a Flask `before_request`/`after_request` middleware emits `RequestCount`, `ErrorCount`, and `Latency` directly to CloudWatch via boto3. Metrics are published both with an `Endpoint` dimension (per-route breakdown) and without dimensions (dashboard totals).

### CI/CD pipeline design

The pipeline uses four sequential gates — test, scan, build, deploy-staging — with a fifth (production) requiring manual approval. Security scanning runs on every push and PR, not just on merge, so vulnerabilities are caught early.

---

## Challenges and Resolutions

| Challenge | Resolution |
|---|---|
| Terraform 0.12 incompatibility with `required_providers` and `sensitive` variables | Removed the `terraform {}` block and `sensitive = true` from variables; used only syntax supported by 0.12 |
| S3 backend inaccessible due to lab IAM restrictions | Switched to local backend (`terraform.tfstate` on the server) |
| RDS `db_name` attribute rejected by old AWS provider | Changed to `name` (the attribute name used in older provider versions) |
| EIP `domain = "vpc"` rejected by old AWS provider | Changed to `vpc = true` |
| ALB and RDS `AccessDenied` errors during `terraform apply` | Incrementally identified missing IAM actions and added them to the custom `TerraformDeployPolicy` |
| CloudWatch dashboard `InvalidParameterInput` — missing `region` field | Added `"region"` to every metric widget's `properties` block in the dashboard JSON |
| Flask unit test `ModuleNotFoundError` | Added `conftest.py` with `sys.path.insert` so pytest can find the `app` module |
| Flask CVE in dependency scan (pip-audit) | Upgraded `flask` from 3.0.3 to 3.1.3 which patched the vulnerability |
| Slack webhook returning exit code 3 (URL malformed) | The secret was accidentally set to the full `curl` command instead of just the URL — deleted and re-created the secret with only the webhook URL |
| Custom CloudWatch metrics not appearing in dashboard | Dashboard widgets queried metrics without dimensions, but the middleware published only dimensioned metrics — fixed by also publishing dimension-less aggregate metrics alongside the per-endpoint ones |
| EC2 public IP changes on every `terraform apply` | Updated `EC2_HOST` GitHub secret after each infrastructure re-apply |
