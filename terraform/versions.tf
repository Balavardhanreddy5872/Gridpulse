# GridPulse - Milestone 6: the application's Google Cloud infrastructure as code.
#
#   cd terraform
#   terraform init          # state lives in gs://gridpulse-509202-tfstate (see backend below)
#   terraform plan          # refresh is on by default: compares this code with what is live
#   terraform apply
#
# Everything created by hand in Milestones 3-5 (gcloud scripts in deploy/m4 and
# deploy/m5) is ADOPTED with the import blocks in imports.tf, so Terraform
# manages the live resources without recreating them. Resources that are new in
# Milestone 6 (monitoring, alerting, the CI/CD identity) are created here.
# What Terraform deliberately does NOT manage, and why: README.md in this folder.

terraform {
  required_version = ">= 1.5.0" # import blocks

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.46"
    }
  }

  # Remote state in a private, versioned bucket (created once by
  # deploy/m6/01_bootstrap_state.sh - Terraform cannot create the bucket that
  # holds its own state). The state is never committed to git.
  backend "gcs" {
    bucket = "gridpulse-509202-tfstate"
    prefix = "gridpulse/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}
