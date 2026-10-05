terraform {
  required_providers {
    akamai = {
      source  = "akamai/akamai"
      version = ">= 8.1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
  required_version = ">= 1.0"
}

provider "akamai" {
  edgerc         = var.edgerc_path
  config_section = var.config_section
}

provider "time" {}

variable "edgerc_path" {
  type    = string
  default = "~/.edgerc"
}

variable "config_section" {
  type    = string
  default = "akamaio"
}

locals {
  group_id    = "grp_300773"
  contract_id = "ctr_F-JOGRS2"
  product_id  = "prd_SPM"
  domain_name = "appsec.work"
  dns_zone    = "appsec.work"
  # hostname    = "videsabottomlineusingterraform.appsec.work"  
  # Define Primary Hostname and Additional SANs here
  primary_hostname = "videsabottomlinesan.appsec.work"  
  additional_sans  = [
    "videsabottomlinesan1.appsec.work",
    "videsabottomlinesan2.appsec.work"
  ]
  # Consolidated list of all SAN hostnames for certificate & property mapping
  san_hostnames    = toset(concat([local.primary_hostname], local.additional_sans))
}

# ==============================================================================
# PHASE 1: CPS ENROLLMENT & TOKEN DISCOVERY
# ==============================================================================

# 1. Create CPS Enrollment
resource "akamai_cps_dv_enrollment" "dv_cert" {
  contract_id                            = local.contract_id
  # common_name                            = local.hostname
  common_name                            = local.primary_hostname
  allow_duplicate_common_name            = false
  # sans                                   = [local.hostname]
  sans                                   = local.additional_sans
  secure_network                         = "enhanced-tls"
  sni_only                               = false
  acknowledge_pre_verification_warnings  = true

  admin_contact {
    first_name       = "Viraj"
    last_name        = "Desai"
    organization     = "Akamai"
    email            = "virajhdesai@gmail.com"
    phone            = "437-778-5859"
    address_line_one = "87 Morningmist St"
    city             = "Brampton"
    region           = "ON"
    postal_code      = "L6R2A8"
    country_code     = "CA"
  }

  certificate_chain_type = "default"

  csr {
    country_code        = "CA"
    city                = "Brampton"
    organization        = "Akamai"
    organizational_unit = "GS"
    state               = "ON"
  }

  network_configuration {
    disallowed_tls_versions = ["TLSv1", "TLSv1_1"]
    geography               = "core"
    must_have_ciphers       = "ak-akamai-2020q1"
    ocsp_stapling           = "on"
    preferred_ciphers       = "ak-akamai-2020q1"
  }

  signature_algorithm = "SHA-256"

  tech_contact {
    first_name       = "Viraj"
    last_name        = "Desai"
    organization     = "AkamaiTechnologies"
    email            = "videsa@akamai.com"
    phone            = "437-778-5859"
    address_line_one = "87 Morningmist St"
    city             = "Brampton"
    region           = "ON"
    postal_code      = "L6R2A8"
    country_code     = "CA"
  }

  organization {
    name             = "Akamai"
    phone            = "87-425-2624"
    address_line_one = "145 Broadway 5th Floor"
    city             = "Cambridge"
    region           = "MA"
    postal_code      = "02142"
    country_code     = "US"
  }
}

# Outputs
output "enrollment_id" {
  value = akamai_cps_dv_enrollment.dv_cert.id
}

# output "dns_challenges" {
#   value = data.akamai_cps_dv_enrollment.dv_cert.dns_challenges
# }

# ==============================================================================
# PHASE 2: EDGE DNS TXT RECORD & DV VALIDATION ACKNOWLEDGEMENT
# ==============================================================================

# 1. Create the TXT Challenge Record using a single static instance key
resource "akamai_dns_record" "dv_validation_record" {
  # for_each = {
  #   for idx, challenge in akamai_cps_dv_enrollment.dv_cert.dns_challenges :
  #   local.hostname => challenge
  # }
  # for_each = {
  #   for idx, domain in tolist(local.san_hostnames) :
  #   domain => tolist(akamai_cps_dv_enrollment.dv_cert.dns_challenges)[idx]
  # }
  for_each = local.san_hostnames
  zone       = local.dns_zone
  recordtype = "TXT"  
  # name       = each.value.full_path
  # target     = [each.value.response_body]
  # Safely extract matching challenge full_path; falls back to empty string if missing or empty
  name = try(
    [
      for c in akamai_cps_dv_enrollment.dv_cert.dns_challenges :
      c.full_path if lower(trimsuffix(c.domain, ".")) == lower(trimsuffix(each.key, "."))
    ][0],
    ""
  )

  # Safely extract matching challenge response_body
  target = [
    try(
      [
        for c in akamai_cps_dv_enrollment.dv_cert.dns_challenges :
        c.response_body if lower(trimsuffix(c.domain, ".")) == lower(trimsuffix(each.key, "."))
      ][0],
      ""
    )
  ]
  ttl    = 60

  depends_on = [akamai_cps_dv_enrollment.dv_cert]
}

# 2. Pause 300s for Edge DNS global propagation
resource "time_sleep" "wait_for_dns_propagation" {
  depends_on      = [akamai_dns_record.dv_validation_record]
  create_duration = "300s"
}

# 3. Signal Let's Encrypt / CPS that DNS validation record is live
resource "akamai_cps_dv_validation" "acknowledge_validation" {
  enrollment_id = akamai_cps_dv_enrollment.dv_cert.id

  depends_on = [time_sleep.wait_for_dns_propagation]
}

# ==============================================================================
# PHASE 3: SLOT TRACKING & EDGE HOSTNAME BINDING
# ==============================================================================

# 1. Create CP Code
resource "akamai_cp_code" "cp_code" {
  # name        = "CP-Code-${replace(local.hostname, ".", "-")}"
  name        = "CP-Code-${replace(local.primary_hostname, ".", "-")}"
  contract_id = local.contract_id
  group_id    = local.group_id
  product_id  = local.product_id
}

# 2. POLL: Wait for CPS backend to activate the SSL slot
resource "null_resource" "wait_for_slot_activation" {
  triggers = {
    enrollment_id = akamai_cps_dv_enrollment.dv_cert.id
  }
  provisioner "local-exec" {
    command     = "powershell -ExecutionPolicy Bypass -File ./wait_for_slot.ps1 -EnrollmentId ${akamai_cps_dv_enrollment.dv_cert.id} -ConfigSection ${var.config_section}"
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [akamai_cps_dv_validation.acknowledge_validation]
}

# ==============================================================================
# PHASE 3: EDGE HOSTNAME BINDING
# ==============================================================================

# 1. Brief pause to let Akamai PAPI recognize the newly deployed CPS slot
resource "time_sleep" "wait_for_papi_registration" {
  create_duration = "900s"

  depends_on = [
    null_resource.wait_for_slot_activation
  ]
}

# 2. Create Edge Hostname with mandatory certificate enrollment ID
resource "akamai_edge_hostname" "secure_ehn" {
  for_each = local.san_hostnames

  contract_id   = local.contract_id
  group_id      = local.group_id
  product_id    = local.product_id
  # edge_hostname = "${local.hostname}.edgekey.net"
  edge_hostname = "${each.key}.edgekey.net"
  ip_behavior   = "IPV6_COMPLIANCE"
  certificate = akamai_cps_dv_enrollment.dv_cert.id
  depends_on = [
    time_sleep.wait_for_papi_registration
  ]
}

# 3. Property Rules Definition
data "akamai_property_rules_builder" "main" {
  rules_v2025_07_07 {
    name = "default"
    is_secure = true
    behavior {
      origin {
        origin_type         = "CUSTOMER"
        hostname            = "origin.${local.domain_name}"
        forward_host_header = "REQUEST_HOST_HEADER"
      }
    }
    behavior {
      cp_code {
        value {
          id = tonumber(replace(akamai_cp_code.cp_code.id, "cpc_", ""))
        }
      }
    }
    behavior {
      caching {
        behavior = "NO_STORE"
      }
    }
  }
}

# 4. Delivery Property
resource "akamai_property" "delivery_property" {
  # name        = local.hostname
  name        = local.primary_hostname
  contract_id = local.contract_id
  group_id    = local.group_id
  product_id  = local.product_id
  rule_format = "v2025-07-07"
  rules       = data.akamai_property_rules_builder.main.json

  # hostnames {
  #   cname_type             = "EDGE_HOSTNAME"
  #   cname_from             = local.hostname
  #   cname_to               = "${local.hostname}.edgekey.net"    
  #   cert_provisioning_type = "CPS_MANAGED"
  # }
  dynamic "hostnames" {
    for_each = local.san_hostnames

    content {
      cname_type             = "EDGE_HOSTNAME"
      cname_from             = hostnames.value
      cname_to               = akamai_edge_hostname.secure_ehn[hostnames.value].edge_hostname
      cert_provisioning_type = "CPS_MANAGED"
    }
  }

  depends_on = [ 
    akamai_edge_hostname.secure_ehn
  ]
}

# 5. Activate Property on Staging
resource "akamai_property_activation" "staging_activation" {
  property_id = akamai_property.delivery_property.id
  contact     = ["videsa@akamai.com"]
  version     = akamai_property.delivery_property.latest_version
  network     = "STAGING"
  auto_acknowledge_rule_warnings = true
  note        = "Automated activation for multi-SAN certificate deployment"

  depends_on = [akamai_property.delivery_property]
}