# Certificate-And-Delivery-Properties-Automation
Automated the complete lifecycle of Akamai DVSAN certificates and delivery configuration management via infrastructure as code

Automated the complete lifecycle of Akamai DVSAN certificates and delivery configuration management via infrastructure as code:

    Certificate Provisioning: Automates CPS enrollment and handles the ACME Domain Control Validation (DCV) challenge by dynamically updating Edge DNS records and verifying the token in CPS.

    Hostname Association: Automatically provisions the Edge Hostname upon successful certificate deployment and links the newly issued DVSAN cert.

    Property Deployment: Automatically configures the delivery property and propagates changes to both Staging and Production environments.

    Impact: Eliminates manual operational overhead, enabling full edge-delivery provisioning via standard terraform plan and terraform apply workflows.
