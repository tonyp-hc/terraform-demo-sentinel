####################
##### REMOTE BACKEND 
####################
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "TonyPulickal"

    workspaces {
      name = "ops-tfe-prod"
    }
  }
}

####################
##### DATA 
####################
variable "tfe_token" {}

variable "tfe_hostname" {
  description = "The domain where your TFE is hosted."
  default     = "app.terraform.io"
}

variable "tfe_organization" {
  description = "The TFE organization to apply your changes to."
  default     = "TonyPulickal"
}

provider "tfe" {
  hostname = "${var.tfe_hostname}"
  token    = "${var.tfe_token}"
  version  = "~> 0.6"
}

data "tfe_workspace_ids" "all" {
  names        = ["*"]
  organization = "${var.tfe_organization}"
}

locals {
  workspaces = "${data.tfe_workspace_ids.all.external_ids}" # map of names to IDs
}

####################
##### POLICY SETS
####################
resource "tfe_policy_set" "global" {
  name          = "global"
  description   = "Policies that should be enforced on ALL environments."
  organization  = "${var.tfe_organization}"
  global        = true

  policy_ids = [
    "${tfe_sentinel_policy.passthrough.id}",
    "${tfe_sentinel_policy.limit-cost-by-workspace-type.id}",
    "${tfe_sentinel_policy.require-all-resources-from-pmr.id}",
  ]
}

resource "tfe_policy_set" "aws-global" {
  name          = "aws-global"
  description   = "Policies enforced in ALL AWS environments"
  organization  = "${var.tfe_organization}"

  policy_ids = [
    "${tfe_sentinel_policy.aws-enforce-mandatory-tags.id}",
    "${tfe_sentinel_policy.aws-restrict-ingress-sg-rule-cidr-blocks.id}",
  ]

  workspace_external_ids = [
    "${local.workspaces["digserv-aws-frontend-dev"]}",
    "${local.workspaces["digserv-aws-frontend-prod"]}",
    "${local.workspaces["terraform-demo-vpc"]}",
  ]
}

resource "tfe_policy_set" "aws-prod-compute" {
  name          = "aws-prod-compute"
  description   = "Policies enforced in production AWS compute environments"
  organization  = "${var.tfe_organization}"

  policy_ids = [
    "${tfe_sentinel_policy.aws-prod-restrict-availability-zones.id}",
    "${tfe_sentinel_policy.aws-prod-restrict-ec2-instance-type.id}",
    "${tfe_sentinel_policy.aws-prod-restrict-db-instance-engines.id}",
  ]

  workspace_external_ids = [
    "${local.workspaces["digserv-aws-frontend-prod"]}",
  ]
}

resource "tfe_policy_set" "aws-nonprod-compute" {
  name          = "aws-nonprod-compute"
  description   = "Policies enforced in non-production AWS compute environments"
  organization  = "${var.tfe_organization}"

  policy_ids = [
    "${tfe_sentinel_policy.aws-nonprod-restrict-availability-zones.id}",
    "${tfe_sentinel_policy.aws-nonprod-restrict-ec2-instance-type.id}",
  ]

  workspace_external_ids = [
    "${local.workspaces["digserv-aws-frontend-dev"]}",
  ]
}

#resource "tfe_policy_set" "sentinel" {
#  name         = "sentinel"
#  description  = "Policies that watch the watchman. Enforced only on the workspace that manages policies."
#  organization = "${var.tfe_organization}"
#
#  policy_ids = [
#    "${tfe_sentinel_policy.tfe-policies-only.id}",
#  ]
#
#  workspace_external_ids = [
#    "${local.workspaces["ops-tfe-prod"]}",
#  ]
#}

####################
##### POLICIES
####################

## Test/experimental policies:

resource "tfe_sentinel_policy" "passthrough" {
  name         = "passthrough"
  description  = "Just passing through! Always returns 'true'."
  organization = "${var.tfe_organization}"
  policy       = "${file("./passthrough.sentinel")}"
  enforce_mode = "advisory"
}

## Sentinel management policies:

#resource "tfe_sentinel_policy" "tfe-policies-only" {
#  name         = "tfe-policies-only"
#  description  = "The Terraform config that manages Sentinel policies must not use the authenticated tfe provider to manage non-Sentinel resources."
#  organization = "${var.tfe_organization}"
#  policy       = "${file("./tfe-policies-only.sentinel")}"
#  enforce_mode = "hard-mandatory"
#}

## Global policies
resource "tfe_sentinel_policy" "limit-cost-by-workspace-type" {
  name          = "limit-cost-by-workspace-type"
  description   = "Cap max potential cost by workspace environment."
  organization  = "${var.tfe_organization}"
  policy        = "${file("./global/limit-cost-by-workspace-type.sentinel")}"
  enforce_mode  = "hard-mandatory"
}

resource "tfe_sentinel_policy" "require-all-resources-from-pmr" {
  name          = "require-all-resources-from-pmr"
  description   = "Enforce that all resources originate from Private Module Registry."
  organization  = "${var.tfe_organization}"
  policy        = "${file("./global/require-all-resources-from-pmr.sentinel")}"
  enforce_mode  = "hard-mandatory"
}

## AWS Global Policies
resource "tfe_sentinel_policy" "aws-enforce-mandatory-tags" {
  name          = "aws-enforce-mandatory-tags"
  description   = "Enforce that all AWS resources have required tags."
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/enforce-mandatory-tags.sentinel")}"
  enforce_mode  = "hard-mandatory"
}

resource "tfe_sentinel_policy" "aws-restrict-ingress-sg-rule-cidr-blocks" {
  name          = "aws-restrict-ingress-sg-rule-cidr-blocks"
  description   = "Enforce that no AWS resources allow inbound traffic to the internet."
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/restrict-ingress-sg-rule-cidr-blocks.sentinel")}"
  enforce_mode  = "hard-mandatory"
}

## AWS Production Policies
resource "tfe_sentinel_policy" "aws-prod-restrict-availability-zones" {
  name          = "aws-prod-restrict-availability-zones"
  description   = "Enforce that all AWS resources are created in approved AZs."
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/prod/restrict-availability-zones.sentinel")}"
  enforce_mode  = "hard-mandatory"
}

resource "tfe_sentinel_policy" "aws-prod-restrict-ec2-instance-type" {
  name          = "aws-prod-restrict-ec2-instance-type"
  description   = "Enforce that all AWS EC2 instances are approved types." 
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/prod/restrict-ec2-instance-type.sentinel")}"
  enforce_mode  = "soft-mandatory"
}

resource "tfe_sentinel_policy" "aws-prod-restrict-db-instance-engines" {
  name          = "aws-prod-restrict-db-instance-engines"
  description   = "Enforce that all AWS RDS instances are approved types." 
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/prod/restrict-db-instance-engines.sentinel")}"
  enforce_mode  = "hard-mandatory"
}

## AWS Non-Production Policies
resource "tfe_sentinel_policy" "aws-nonprod-restrict-availability-zones" {
  name          = "aws-nonprod-restrict-availability-zones"
  description   = "Enforce that all AWS resources are created in approved AZs."
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/nonprod/restrict-availability-zones.sentinel")}"
  enforce_mode  = "soft-mandatory"
}

resource "tfe_sentinel_policy" "aws-nonprod-restrict-ec2-instance-type" {
  name          = "aws-nonprod-restrict-ec2-instance-type"
  description   = "Enforce that all AWS EC2 instances are approved types." 
  organization  = "${var.tfe_organization}"
  policy        = "${file("./aws/nonprod/restrict-ec2-instance-type.sentinel")}"
  enforce_mode  = "advisory"
}
