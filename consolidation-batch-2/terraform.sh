#!/usr/bin/env bash
# Terraform checks behind the SSH key section that consolidation batch 2 added
# to the Terraform guide: plan an AWS key pair and a Google Cloud VM that get a
# public key from a file. Uses fake credentials, so nothing is created.
set -uo pipefail

run() { echo; echo "\$ $*"; eval "$@" 2>&1; echo "[exit $?]"; }

TF_VERSION=1.15.8
curl -sSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
unzip -oq /tmp/tf.zip -d /tmp/tf && sudo install -m 0755 /tmp/tf/terraform /usr/local/bin/terraform

WORK=$(mktemp -d)
cd "$WORK"
trap 'rm -rf "$WORK"' EXIT
mkdir -p keys
ssh-keygen -q -t ed25519 -N '' -C deploy -f keys/deploy

cat > main.tf <<'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

# fake credentials: plan only, nothing is created
provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "AKIAEXAMPLE"
  secret_key                  = "example"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

provider "google" {
  project      = "demo-project"
  region       = "europe-west1"
  access_token = "fake"
}

variable "ssh_public_key_path" {
  type    = string
  default = "keys/deploy.pub"
}

resource "aws_key_pair" "deploy" {
  key_name   = "deploy"
  public_key = file(var.ssh_public_key_path)
}

resource "google_compute_instance" "web" {
  name         = "web-1"
  machine_type = "e2-small"
  zone         = "europe-west1-b"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
  }

  metadata = {
    ssh-keys               = "deploy:${trimspace(file(var.ssh_public_key_path))}"
    block-project-ssh-keys = "true"
  }
}
EOF

run terraform version
run "terraform init -input=false -no-color | grep -E 'Installed|initialized'"
run terraform validate -no-color
run "terraform plan -input=false -no-color -refresh=false | grep -E 'will be created|public_key|ssh-keys|block-project|Plan:'"
run "terraform plan -input=false -no-color -refresh=false | tail -25"
