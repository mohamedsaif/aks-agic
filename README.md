# AKS **App Gateway Ingress Controller" Deployment
Security focused deployment of AGIC on AKS where I'm trying to achieve the following:

- Provisioning for Azure Resources:
    - App Gateway v2
    - Azure Key Vault
    - AKS cluster
    - Azure Managed Identities
- Obtaining TLS certificates (end-to-end encryption)
    - Frontend certificate (saved in Azure Key Vault and used by App Gateway)
    - Backend certificate (saved in AKS and configured in App Gateway)
- Configuring sample service deployment for end-to-end encryption
    - Azure Key Vault configuration (uploading certificate)
    - App Gateway Configuration (Key Vault access to certificate)
    - AKS configuration (AGIC, Pod Identity, Backend Certificate)

