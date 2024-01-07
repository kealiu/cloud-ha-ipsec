# cloud-ha-ipsec

A High-Available(by Keepalived) Implementation of IPsec(by Strongswan) VPN 

# Usage

1. edit the `terraform.tfvars`
2. `terraform apply` and yes
3. login the system, and update `/etc/ipsec.conf`
4. `sudo ipsec restart to start the ipsec`
4. `systemctl status keepalived` to check the current role of node

The ndoe will update `route table` directly, by replace peer ENI with master node's ENI. 

and, it will also send notification via SNS, which you can subscript and trigger some webhook
