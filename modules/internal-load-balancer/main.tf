# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY AN INTERNAL LOAD BALANCER
# This module deploys an Internal TCP/UDP Load Balancer
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

terraform {
  # This module has been updated with 0.12 syntax, which means it is no longer compatible with any versions below 0.12.
  required_version = ">= 0.12"
}

# ------------------------------------------------------------------------------
# CREATE FORWARDING RULE
# ------------------------------------------------------------------------------

resource "google_compute_forwarding_rule" "default" {
  provider              = google-beta
  project               = var.project
  name                  = var.name
  region                = var.region
  network               = var.network == "" ? "default" : var.network
  subnetwork            = var.subnetwork
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.default.self_link
  ip_address            = var.ip_address
  ip_protocol           = var.protocol
  ports                 = var.ports

  # If service label is specified, it will be the first label of the fully qualified service name.
  # Due to the provider failing with an empty string, we're setting the name as service label default
  service_label = var.service_label == "" ? var.name : var.service_label

  # This is a beta feature
  labels = var.custom_labels
}

# ------------------------------------------------------------------------------
# CREATE BACKEND SERVICE
# ------------------------------------------------------------------------------

resource "google_compute_region_backend_service" "default" {
  project          = var.project
  name             = var.name
  region           = var.region
  protocol         = var.protocol
  timeout_sec      = 10
  session_affinity = var.session_affinity

  backend = [var.backends]

  health_checks = [
    compact(
      concat(
        google_compute_health_check.tcp.*.self_link,
        google_compute_health_check.http.*.self_link
      )
  )[0]]
}

# ------------------------------------------------------------------------------
# CREATE HEALTH CHECK - ONE OF ´http´ OR ´tcp´
# ------------------------------------------------------------------------------

resource "google_compute_health_check" "tcp" {
  count = var.http_health_check ? 0 : 1

  project = var.project
  name    = "${var.name}-hc"

  tcp_health_check {
    port = var.health_check_port
  }
}

resource "google_compute_health_check" "http" {
  count = var.http_health_check ? 1 : 0

  project = var.project
  name    = "${var.name}-hc"

  http_health_check {
    port = var.health_check_port
  }
}

# ------------------------------------------------------------------------------
# CREATE FIREWALLS FOR THE LOAD BALANCER AND HEALTH CHECKS
# ------------------------------------------------------------------------------

# Load balancer firewall allows ingress traffic from instances tagged with any of the ´var.source_tags´
resource "google_compute_firewall" "load_balancer" {
  project = var.network_project == "" ? var.project : var.network_project
  name    = "${var.name}-ilb-fw"
  network = var.network

  allow {
    protocol = lower(var.protocol)
    ports    = var.ports
  }

  # Source tags defines a source of traffic as coming from the primary internal IP address
  # of any instance having a matching network tag.
  source_tags = var.source_tags

  # Target tags define the instances to which the rule applies
  target_tags = var.target_tags
}

# Health check firewall allows ingress tcp traffic from the health check IP addresses
resource "google_compute_firewall" "health_check" {
  project = var.network_project == "" ? var.project : var.network_project
  name    = "${var.name}-hc"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = [var.health_check_port]
  }

  # These IP ranges are required for health checks
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  # Target tags define the instances to which the rule applies
  target_tags = var.target_tags
}

