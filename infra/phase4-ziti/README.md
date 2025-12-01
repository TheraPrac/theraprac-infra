# Phase 4: Ziti Network Infrastructure

Deploys OpenZiti controller and edge routers for zero-trust networking.

## Status

📋 **Planned**

## Depends On

- Phase 1 (VPC)
- Phase 2 (VPC Endpoints)
- Phase 3 (IAM)

## Planned Resources

### Ziti Controller

- EC2 instance in non-prod Ziti subnet
- PKI infrastructure for certificates
- Controller database (embedded or external)

### Ziti Edge Routers

- Edge routers in each Ziti subnet
- Public router for external client access
- Private routers for internal service mesh

### Security Groups

- Controller security group
- Edge router security groups
- Inter-component communication rules

## Ansible Integration

This phase will include Ansible playbooks for:

- Ziti controller installation and configuration
- Edge router enrollment
- Service and identity provisioning
- Certificate management

