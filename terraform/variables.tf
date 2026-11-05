variable "project_id" {
  description = "Google Cloud project that hosts GridPulse."
  type        = string
  default     = "gridpulse-509202"
}

variable "region" {
  description = "Region for the cluster, database, bucket, registry and secrets."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone of the (zonal) Cloud SQL instance."
  type        = string
  default     = "us-central1-a"
}

variable "domain" {
  description = "Public HTTPS hostname of the app (DuckDNS record -> gridpulse-gke-ip)."
  type        = string
  default     = "gridpulse-9.duckdns.org"
}

variable "github_repository" {
  description = "owner/name of the GitHub repository whose pipeline may deploy."
  type        = string
  default     = "Balavardhanreddy5872/Gridpulse"
}

variable "deploy_branch" {
  description = "The only branch whose pipeline runs can obtain Google credentials."
  type        = string
  default     = "main"
}

variable "alert_emails" {
  description = "Team e-mail addresses that receive alert notifications. Set in notification.auto.tfvars (not committed)."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_emails must contain at least one valid e-mail address (see notification.auto.tfvars.example)."
  }
}

variable "http_5xx_alert_threshold" {
  description = "Alert when MORE than this many user-facing HTTP 5xx responses happen within 5 minutes."
  type        = number
  default     = 2
}
