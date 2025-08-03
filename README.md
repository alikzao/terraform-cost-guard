
# Terraform Cost Guard

[![Terraform Version](https://img.shields.io/badge/Terraform-%E2%89%A5%201.8-blue?logo=terraform)](https://www.terraform.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Stop paying for idle AWS compute in **under 5 minutes**. *Terraform Cost Guard* discovers forgotten EC2 instances and EBS volumes, then stops them automatically—so you only pay for what you actually use.

* **‑37 % AWS spend** in just 14 days on our test account
* Dry‑run by default—zero risk
* One Terraform module + one Grafana panel = done

---

## 🚀 Quick Start

```hcl
module "cost_guard" {
  source        = "github.com/your‑org/terraform-cost-guard"

  # Core settings
  idle_days     = 7                    # How many idle days before action
  regions       = ["us‑east‑1"]        # Regions to scan
  exclude_tags  = ["production"]       # Resources with these tags are ignored

  # Safety
  dry_run       = true                 # Set to false to actually stop instances
}
```

```bash
terraform init && terraform apply -auto-approve
```

---

## 🎬 Live Demo

[![Before/After screenshot](assets/before-after.png)](assets/before-after.png)

▶ **90‑second Loom walkthrough:** [https://loom.com/share/REPLACE\_ME](https://loom.com/share/REPLACE_ME)

*Example result: daily spend dropped from **\$12.40** to **\$7.85** (–37%) within two weeks.*

---

## 🛠️ How It Works

1. **Discovery** – A Lambda (built via this module) queries CloudWatch metrics and tags to find idle resources.
2. **Filter** – If CPU / IOPS ≈ 0 for `idle_days`, the resource is flagged.
3. **Action** – `ec2 stop‑instances` & `ebs disable-volume` (or report‑only in dry‑run).
4. **Dashboard** – Cost Explorer data feeds a minimal Grafana panel (`grafana-dash.json`).

---

## 🔧 Inputs

| Name           | Description                                                | Type           | Default         |
| -------------- | ---------------------------------------------------------- | -------------- | --------------- |
| `idle_days`    | Days of zero activity before a resource is considered idle | `number`       | `7`             |
| `regions`      | AWS regions to inspect                                     | `list(string)` | `["us‑east‑1"]` |
| `exclude_tags` | Tag keys that exclude resources from Guard                 | `list(string)` | `[]`            |
| `dry_run`      | If true, only report idle resources without stopping them  | `bool`         | `true`          |

## 📤 Outputs

| Name                      | Description                            |
| ------------------------- | -------------------------------------- |
| `stopped_instances`       | IDs of EC2 instances that were stopped |
| `estimated_savings_daily` | Approx. USD saved per day              |

---

## 📈 Dashboard


### Adding permissions to your AWS credentials:

For MAC users, add the following to your `~/.aws/credentials` file:

```bash
docker run -d -p 3000:3000 --name=grafana \
-v "$HOME/.aws:/usr/share/grafana/.aws:ro" grafana/grafana

Check conection to AWS
docker exec -u grafana -it grafana cat /usr/share/grafana/.aws/credentials
```

1. Import `grafana-dash.json` into Grafana ≥ v10.
2. Set variable `$AWS_ACCOUNT_ID` to your account ID.
3. Watch the cost line drop like a stone 🪨.

---

## 🧰 Development & Tests

```bash
make test   # unit tests
make lint   # terraform fmt & tflint
make release # tag & publish v0.x.x
```

---

## 📜 License

MIT © Oleksandr Zakrevskyi


## Logs after stop

START RequestId: a4411e9d-0a26-4090-93b3-4229ce6ec047 Version: $LATEST
2025-08-01T19:25:11.169Z	a4411e9d-0a26-4090-93b3-4229ce6ec047	INFO	EBS vol-09751ceb4caa0862c idle (dryRun=false)
2025-08-01T19:25:11.417Z	a4411e9d-0a26-4090-93b3-4229ce6ec047	INFO	EBS vol-0aa993e3c3cbad968 idle (dryRun=false)
2025-08-01T19:25:11.570Z	a4411e9d-0a26-4090-93b3-4229ce6ec047	INFO	EBS vol-08f211f3e651d9d82 idle (dryRun=false)
2025-08-01T19:25:11.692Z	a4411e9d-0a26-4090-93b3-4229ce6ec047	INFO	Projected (remaining) until the end of the month: $12.00
2025-08-01T19:25:11.692Z	a4411e9d-0a26-4090-93b3-4229ce6ec047	INFO	full-month: $12.00
END RequestId: a4411e9d-0a26-4090-93b3-4229ce6ec047
REPORT RequestId: a4411e9d-0a26-4090-93b3-4229ce6ec047	Duration: 3190.16 ms	Billed Duration: 3191 ms	Memory Size: 128 MB	Max Memory Used: 128 MB	Init Duration: 842.33 ms

## 💰 Cost Comparison: AWS vs. Bare metal
If you want total savings, then compare bare metal and solutions from Amazon

| Component                     | AWS (On-Demand, **us-east-1**)                                                          | Hetzner bare-metal                                                                |
| ----------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| **Compute (services + jobs)** | 20 × m6i.large → **\$1 402 / mo** ([Amazon Web Services][1])                            | 3 × AX102 (32c / 128 GB) → **€ 327 ≈ \$356 / mo**   (+ €117 setup) ([Hetzner][2]) |
| **Kubernetes control-plane**  | Amazon EKS \$0.10 h → **\$73 / mo** ([Amazon Web Services][3])                          | kubeadm on same nodes → **\$0**                                                   |
| **Load balancer**             | ALB \$0.0225 h + 1 LCU ≈ **\$32 / mo** ([Amazon Web Services][4])                       | HAProxy / Traefik → **\$0**                                                       |
| **Redis cache**               | ElastiCache (3 × cache.r6g.large \$0.165 h) → **\$361 / mo** ([Amazon Web Services][5]) | Redis in pods/VM → **\$0**                                                        |
| **Kafka queue**               | MSK 3 × kafka.m5.large \$0.21 h + 1 TB EBS → **\$569 / mo** ([Amazon Web Services][6])  | Kafka on same servers → **\$0**                                                   |
| **PostgreSQL**                | RDS db.r6i.large \$0.29 h → **\$211 / mo** ([Amazon Web Services][7])                   | Postgres in Docker → **\$0**                                                      |
| **MongoDB**                   | DocumentDB (2 × db.r5.large) → **\$445 / mo** ([Amazon Web Services][8])                | MongoDB self-host → **\$0**                                                       |
| **Columnar analytics**        | Redshift RA3.xlplus \$1.086 h → **\$793 / mo** ([Amazon Web Services][9])               | ClickHouse on same nodes → **\$0**                                                |
| **Object storage**            | S3 5 TB @ \$0.023 GB → **\$115 / mo** ([Amazon Web Services][10])                       | Storage Box BX21 5 TB → **€ 10.9 ≈ \$12 / mo** ([Hetzner][11])                    |
| **DNS**                       | Route 53 10 zones → **\$5 / mo** ([Amazon Web Services][12])                            | Hetzner DNS → **\$0**                                                             |
| **Observability**             | CloudWatch ≈ **\$15 / mo** ([Amazon Web Services][1])                                   | Prometheus + Grafana → **\$0**                                                    |
| **Egress traffic (10 TB)**    | \$0.09 GB → **\$913 / mo** ([Amazon Web Services][13])                                  | 20 TB included → **\$0**                                                          |
| ***Monthly total***           | **≈ \$4 485**                                                                           | **≈ \$368**                                                                       |

[1]: https://aws.amazon.com/ec2/pricing/on-demand/ "EC2 On-Demand Instance Pricing – Amazon Web Services"
[2]: https://www.hetzner.com/news/new-amd-ryzen-7950-server/?utm_source=chatgpt.com "UPGRADE TO THE FUTURE: THE NEW AX102 DEDICATED SERVER WITH ... - Hetzner"
[3]: https://aws.amazon.com/eks/pricing/?utm_source=chatgpt.com "Amazon EKS Pricing"
[4]: https://aws.amazon.com/elasticloadbalancing/pricing/?utm_source=chatgpt.com "Elastic Load Balancing pricing"
[5]: https://aws.amazon.com/elasticache/pricing/?utm_source=chatgpt.com "Pricing for Amazon ElastiCache"
[6]: https://aws.amazon.com/msk/pricing/?utm_source=chatgpt.com "Amazon MSK pricing - Managed Apache Kafka"
[7]: https://aws.amazon.com/rds/postgresql/pricing/?utm_source=chatgpt.com "Amazon RDS for PostgreSQL Pricing"
[8]: https://aws.amazon.com/documentdb/pricing/ "Amazon DocumentDB Pricing - Amazon Web Services"
[9]: https://aws.amazon.com/blogs/big-data/introducing-amazon-redshift-ra3-xlplus-nodes-with-managed-storage/?utm_source=chatgpt.com "Introducing Amazon Redshift RA3.xlplus nodes with managed storage"
[10]: https://aws.amazon.com/s3/pricing/ "Amazon S3 Pricing - Cloud Object Storage - AWS"
[11]: https://www.hetzner.com/dedicated-rootserver/matrix-sx/?utm_source=chatgpt.com "Storage Server – High-Capacity Dedicated Hosting"
[12]: https://aws.amazon.com/route53/pricing/ "Amazon Route 53 pricing - Amazon Web Services"
[13]: https://aws.amazon.com/ec2/pricing/on-demand/?utm_source=chatgpt.com "EC2 On-Demand Instance Pricing"
