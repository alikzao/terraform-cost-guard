
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

[![Before/After screenshot](assets/cost-explorer1.png)](assets/cost-explorer1.png)

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

[![Before/After screenshot](assets/setup-gr-in-aws.png)](assets/setup-gr-in-aws.png)


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


## 📊 Extended description Grafana: Setup & Usage

This module ships with a ready-to-import dashboard JSON. You can use Grafana with a **quick path** (Cost data source or built-in cost alerts) or a **power path** (Athena + CUR) for richer analytics.

### 1) Install Grafana (macOS)

**Option A — Docker (quick):**

```bash
docker run -d --name grafana -p 3000:3000 \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -v $(pwd)/grafana/provisioning:/etc/grafana/provisioning \
  -v $(pwd)/grafana/dashboards:/var/lib/grafana/dashboards \
  grafana/grafana:10.4.0
```

Open [http://localhost:3000](http://localhost:3000) (admin / admin).

**Option B — Native (Homebrew):**

```bash
brew install grafana
brew services start grafana
```

Open [http://localhost:3000](http://localhost:3000).

> Tip: If you don’t need provisioning, you can omit the mounted folders in Docker.

---

### 2) Pick your data path

**Quick path — use Cost data source / built-in cost alerts**

* If your Grafana has an **AWS Cost Explorer** (or **Grafana Cloud Cost**) data source available, add it and you’ll get daily spend out-of-the-box.
* You can then attach an **Alert** to the spend panel (e.g., trigger if daily spend > budget).
* Alternatively, skip Grafana entirely and enable **AWS Budgets** and **Cost Anomaly Detection** in the AWS console for native cost alerts.

**Power path — Athena over the AWS Cost & Usage Report (CUR)**

* Recommended when you want custom aggregations, tags/linked-account splits, or multi-panel analytics.

---

### 3) Configure the data source

#### A. AWS Cost (if available in your Grafana)

1. **Add data source** → *AWS Cost Explorer* or *Grafana Cloud Cost*.
2. **Auth**: Use an IAM role on the host or static keys with read-only permissions to Cost Explorer.
3. **Region**: Cost Explorer is global but API endpoints live in `us-east-1`; set that region if prompted.
4. **Test & Save**.

#### B. Athena + CUR (advanced)

1. **Enable CUR**: In AWS Billing → Cost & Usage Reports, create a report to S3 (prefer **Parquet**, daily, with partitions).
2. **Glue Catalog**: Let AWS auto-create the Glue table, or create it manually.
3. **Athena**: Create a **workgroup** and set **Query results location** (e.g., `s3://athena-results-<acct>-<region>/query-results/`).
4. **Query**: Build a daily spend view. Example:

```sql
-- Daily unblended cost
SELECT date_trunc('day', line_item_usage_start_date) AS day,
       SUM(line_item_unblended_cost)                AS cost_usd
FROM   aws_cur.your_cur_table
WHERE  year = 2025  -- or filter by date range
GROUP BY 1
ORDER BY 1;
```

5. **Grafana data source**: Add **Amazon Athena** data source and point to your **Workgroup**, **Catalog** (usually `AwsDataCatalog`), and **Database**.

---

### 4) Import the dashboard JSON

You can use the repository dashboard as-is:

1. In Grafana → **Dashboards → Import**.
2. Upload `grafana/grafana-dash.json` (exported with **Export for sharing externally**).
3. When prompted, **select your data source** (Cost or Athena).
4. Click **Import**. Done.

> The dashboard expects a daily series named like `cost_by_date` or the SQL above aliased as `cost_usd`. You can edit the query in the panel if your field names differ.

---

### 5) Optional: provisioning for one-click setup

Provisioning lets Grafana auto-create data sources and dashboards at startup.

**Datasource provisioning (example for Athena):**

```yaml
# grafana/provisioning/datasources/ds.yaml
apiVersion: 1

datasources:
  - name: Athena (Cost Guard)
    type: grafana-athena-datasource
    isDefault: false
    editable: true
    jsonData:
      defaultRegion: ${AWS_REGION}
      workgroup: ${ATHENA_WORKGROUP}
      catalog: ${ATHENA_CATALOG}
      database: ${ATHENA_DATABASE}
      outputLocation: ${ATHENA_OUTPUT}
```

**Dashboard provisioning (optional):**

```yaml
# grafana/provisioning/dashboards/dash.yaml
apiVersion: 1

providers:
  - name: CostGuard
    type: file
    disableDeletion: true
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
```

Place `grafana-dash.json` under `grafana/dashboards` and mount that folder for Docker (see install command).

---

### 6) Alerts

* **Quick**: On the cost panel, toggle **Alert** and create a rule like “Daily spend > \$X for 1h”. Use email/Slack/Teams notifiers.
* **Athena-based**: Use a time series query (e.g., last 24h spend) and create an alert rule on the resulting series. Schedule the rule at a cadence that matches your data freshness (CUR often lags by a few hours).
* **AWS-native**: If you prefer not to use Grafana for alerting, enable **AWS Budgets** and **Cost Anomaly Detection** in the AWS console.

---

### 7) Files to include in the repo

```
/grafana/
  grafana-dash.json                  # exported with "Export for sharing externally"
  /provisioning/datasources/ds.yaml  # optional
  /provisioning/dashboards/dash.yaml # optional
/athena/
  cost_daily.sql                     # example query
/assets/
  before-after.png
```

### 8) Troubleshooting

* **No data**: CUR can lag; give it a few hours. Ensure the SQL filters (year/month/date) match your data.
* **Import errors**: Re-export the dashboard with **Export for sharing externally** to strip local UIDs.
* **Region issues**: Cost Explorer is effectively `us-east-1`. Athena runs in the region of your S3/Glue setup.
* **Auth**: Prefer IAM roles over static keys when possible.

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
