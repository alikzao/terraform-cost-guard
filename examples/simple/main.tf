module "cost_guard" {
  source = "../../modules/cost-guard"

  regions             = ["eu-central-1"]
  idle_threshold_days = 3             # for example, 2 days
  exclude_tags        = ["DoNotStop", "Environment"]
  dry_run             = false
  profile             = "default"     # or AWS CLI profile name if needed
}

