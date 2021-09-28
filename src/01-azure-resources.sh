##############
# Parameters #
##############

# General
PREFIX=agic-dev
LOCATION=westeurope
RG=$PREFIX-rg
UNIQUE_ID=14072
echo "Unique id: " $UNIQUE_ID

# Network
VNET_NAME=$PREFIX-vnet
VNET_CIDR=10.170.0.0/23
AKS_SUBNET=aks
AKS_SUBNET_CIDR=10.170.0.0/24
APPGW_SUBNET=appgw
# minimum capacity for App Gateway subnet is /27
APPGW_SUBNET_CIDR=10.170.1.0/27
PE_SUBNET=private-endpoints
PE_SUBNET_CIDR=10.170.1.32/27

# Key Vault
KEY_VAULT_NAME=$PREFIX-$UNIQUE_ID-kv
echo $KEY_VAULT_NAME

# App Gateway
APPGW=$PREFIX-appgw
APPGW_PRIVATE_IP=10.170.1.4
APPGW_PUBLIC_IP_NAME=$APPGW-pip

# Container Registry
CONTAINER_REGISTRY_NAME=$(echo $PREFIX-$UNIQUE_ID-acr | sed "s/-//g")
echo $CONTAINER_REGISTRY_NAME
# AKS
AKS_NAME=$PREFIX-aks
AKS_MI_NAME=$AKS_NAME-mi

# AGIC Managed Identity
AGIC_MI_NAME=$APPGW-mi

#########
# Login #
#########

az Login
az account set --subscription "SUB-NAME"

##################
# Resource Group #
##################

az group create --name $RG --location $LOCATION

###################
# Virtual Network #
###################

# Creating our main virtual network
az network vnet create \
    --resource-group $RG \
    --name $VNET_NAME \
    --address-prefixes $VNET_CIDR

# Default AKS subnet
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $AKS_SUBNET \
    --address-prefix $AKS_SUBNET_CIDR

# App Gateway subnet
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $APPGW_SUBNET \
    --address-prefix $APPGW_SUBNET_CIDR

# Create subnet for private endpoints (for Azure Key Vault)
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $PE_SUBNET \
    --address-prefix $PE_SUBNET_CIDR

VNET_ID=$(az network vnet show \
    --resource-group $RG \
    --name $VNET_NAME \
    --query id --out tsv)
echo $VNET_ID

AKS_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $AKS_SUBNET \
    --query id --out tsv)
echo $AKS_SUBNET_ID

APPGW_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $APPGW_SUBNET \
    --query id --out tsv)
echo $APPGW_SUBNET_ID

PE_SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $PE_SUBNET \
    --query id --out tsv)
echo $PE_SUBNET_ID

az network vnet subnet update \
    --resource-group $RG \
    --name $PE_SUBNET \
    --vnet-name $VNET_NAME \
    --disable-private-endpoint-network-policies true

#############
# Key Vault #
#############

# New keyvault
az keyvault create \
    --name $KEY_VAULT_NAME \
    --resource-group $RG \
    --enable-soft-delete true \
    --location $LOCATION

KEY_VAULT_ID=$(az keyvault show --name $KEY_VAULT_NAME --query id -o tsv)
echo $KEY_VAULT_ID

# If you want to activate key vault firewall, run the following command:
# az keyvault update -n $KEY_VAULT_NAME -g $RG --default-action deny

# Key vault private endpoint
az network private-dns zone create --resource-group $RG --name privatelink.vaultcore.azure.net
az network private-dns link vnet create --resource-group $RG --virtual-network $VNET_NAME --zone-name privatelink.vaultcore.azure.net --name $KEY_VAULT_NAME-dns --registration-enabled true

az network private-endpoint create \
    --resource-group $RG \
    --subnet $PE_SUBNET_ID \
    --name $KEY_VAULT_NAME-pe \
    --private-connection-resource-id $KEY_VAULT_ID \
    --group-ids vault --connection-name $KEY_VAULT_NAME-to-$VNET_NAME --location $LOCATION

# Adding a private zone records
# Determine the Private Endpoint IP address
PE_NIC=$(az network private-endpoint show -g $RG -n $KEY_VAULT_NAME-pe --query networkInterfaces[0].id -o tsv)
echo $PE_NIC
PE_NIC_IP=$(az network nic show --ids $PE_NIC --query ipConfigurations[0].privateIpAddress -o tsv)
echo $PE_NIC_IP

# https://docs.microsoft.com/azure/dns/private-dns-getstarted-cli#create-an-additional-dns-record
az network private-dns zone list -g $RG
az network private-dns record-set a add-record -g $RG -z "privatelink.vaultcore.azure.net" -n $KEY_VAULT_NAME -a $PE_NIC_IP
az network private-dns record-set list -g $RG -z "privatelink.vaultcore.azure.net"

# From home/public network, you wil get a public IP. If inside a vnet with private zone, nslookup will resolve to the private ip.
nslookup $KEY_VAULT_NAME.vault.azure.net
nslookup $KEY_VAULT_NAME.privatelink.vaultcore.azure.net

###############
# App Gateway #
###############

# I will be using the Application Gateway in dual mode, Public and Private endpoints

# Create public IP for the gateway. 
# Using standard sku allow extra security as it is closed by default and allow traffic through NSGs
# More info here: https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-ip-addresses-overview-arm
az network public-ip create \
    -g $RG \
    -n $APPGW_PUBLIC_IP_NAME \
    -l $LOCATION \
    --sku Standard

# WAF policy
# New approach is to create the waf policy as external resource then associate it with AppGW
WAF_POLICY_NAME=$PREFIX-waf-policy
az network application-gateway waf-policy create \
  --name $WAF_POLICY_NAME \
  --resource-group $RG

az network application-gateway waf-policy managed-rule rule-set add \
  --policy-name $WAF_POLICY_NAME \
  --resource-group $RG \
  --type Microsoft_BotManagerRuleSet --version 0.1

# Check the added managed rules:
az network application-gateway waf-policy managed-rule rule-set list \
  --policy-name $WAF_POLICY_NAME \
  --resource-group $RG

# By default, WAF policy is in detection mode. You can update it via this:
az network application-gateway waf-policy policy-setting update \
  --policy-name $WAF_POLICY_NAME \
  --resource-group $RG \
  --mode Prevention

# Provision the app gateway
# Note to maintain SLA, you need to set --min-capacity to at least 2 instances
# Azure Application Gateway must be v2 SKUs
# App Gateway can be used as native kubernetes ingress controller: https://azure.github.io/application-gateway-kubernetes-ingress/
# In earlier step we provisioned a vNet with a subnet dedicated for App Gateway.

az network application-gateway create \
  --name $APPGW \
  --resource-group $RG \
  --location $LOCATION \
  --min-capacity 1 \
  --frontend-port 80 \
  --http-settings-cookie-based-affinity Disabled \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --routing-rule-type Basic \
  --sku WAF_v2 \
  --private-ip-address $APPGW_PRIVATE_IP \
  --public-ip-address $APPGW_PUBLIC_IP_NAME \
  --subnet $APPGW_SUBNET \
  --vnet-name $VNET_NAME \
  --waf-policy $WAF_POLICY_NAME \
  --query id -o tsv

APPGW_RESOURCE_ID=$(az network application-gateway show -n $APPGW -g $RG --query id -o tsv)
echo $APPGW_RESOURCE_ID

#######
# ACR #
#######

# Create Azure Container Registry (public, great for Dev setup)
az acr create \
    -g $RG \
    -n $CONTAINER_REGISTRY_NAME \
    --sku Basic

CONTAINER_REGISTRY_ID=$(az acr show -n $CONTAINER_REGISTRY_NAME --query id -o tsv)
echo $CONTAINER_REGISTRY_ID

#######
# AKS #
#######

### AKS MI
# Create a MI to be used by AKS 
# NOTE: (you should use this only once)
# NOTE: MI will be created in the central info sec RG
az identity create --name $AKS_MI_NAME --resource-group $RG
AKS_MI=$(az identity show -n $AKS_MI_NAME -g $RG)
# install jq if you don't have it --> sudo apt-get install jq
echo $AKS_MI | jq
AKS_MI_ID=$(echo $AKS_MI | jq -r .principalId)
echo $AKS_MI_ID
AKS_MI_RESOURCE_ID=$(echo $AKS_MI | jq -r .id)
echo $AKS_MI_RESOURCE_ID

### Create new AKS cluster with Azure CNI as network interface
echo "Assigning roles to new MI"
# I will give a contributor access on the resource group that holds directly provisioned resources by AKS
RG_ID=$(az group show --name $RG --query id -o tsv)
echo $RG_AKS_ID
az role assignment create --assignee $AKS_MI_ID --scope $RG_AKS_ID --role "Contributor"
# In better setup, you will assign more granular permissions.
# Example: Granular access (incase the spoke network is shared with other workloads)
# AKS_SUBNET_ID=$(az network vnet subnet show -g $RG_SHARED --vnet-name $PROJ_VNET_NAME --name $AKS_SUBNET_NAME --query id -o tsv)
# AKS_SVC_SUBNET_ID=$(az network vnet subnet show -g $RG_SHARED --vnet-name $PROJ_VNET_NAME --name $SVC_SUBNET_NAME --query id -o tsv)
# AKS_VN_SUBNET_ID=$(az network vnet subnet show -g $RG_SHARED --vnet-name $PROJ_VNET_NAME --name $VN_SUBNET_NAME --query id -o tsv)
# az role assignment create --assignee $AKS_MI_ID --scope $AKS_SUBNET_ID --role "Network Contributor"
# az role assignment create --assignee $AKS_MI_ID --scope $AKS_SVC_SUBNET_ID --role "Network Contributor"
# az role assignment create --assignee $AKS_MI_ID --scope $AKS_VN_SUBNET_ID --role "Network Contributor"

# Review the current SP assignments
az role assignment list \
    --all \
    --assignee $AKS_MI_ID \
    --output json | jq '.[] | {"principalName":.principalName, "roleDefinitionName":.roleDefinitionName, "scope":.scope}'

### AKS supported versions
AKS_VERSION=$(az aks get-versions -l ${LOCATION} --query "orchestrators[?isPreview==null].{Version:orchestratorVersion} | [-1]" -o tsv)
echo $AKS_VERSION

az aks create \
    --resource-group $RG \
    --name $AKS_NAME \
    --location $LOCATION \
    --kubernetes-version $AKS_VERSION \
    --generate-ssh-keys \
    --vnet-subnet-id $AKS_SUBNET_ID \
    --network-plugin azure \
    --network-policy azure \
    --nodepool-name primary \
    --node-count 3 \
    --max-pods 30 \
    --node-vm-size "Standard_D4s_v3" \
    --enable-managed-identity \
    --assign-identity $AKS_MI_RESOURCE_ID

### Get access to AKS
az aks get-credentials --resource-group $RG --name $AKS_NAME

# Test the connection
# Install kubectl if you don't have it --> sudo az aks install-cli
kubectl get nodes


### Installation of AAD Pod Identity
# We will be using "Managed" mode of pod identity, which is the only supported scenario in AKS plugin

# or installing via helm
# Get helm if you don't already have it
# curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
# chmod 700 get_helm.sh
# ./get_helm.sh
# rm get_helm.sh
helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm install aad-pod-identity aad-pod-identity/aad-pod-identity


# Installing via yaml
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml
# For AKS clusters, deploy the MIC and AKS add-on exception by running -
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/mic-exception.yaml

# Or via the AKS add-on
# Making sure the aks-preview extension is installed and/or updated
az extension add --name aks-preview
# Update the extension to make sure you have the latest version installed
az extension update --name aks-preview
# Update AKS cluster with the AAD pod identity plugin
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az aks update -g $RG -n $AKS --enable-pod-identity


#########################
# AGIC Managed Identity #
#########################

az identity create -g $RG -n $AGIC_MI_NAME
AGIC_MI_ID=$(az identity show -g $RG -n $AGIC_MI_NAME --query id)
AGIC_MI_CLIENT_ID=$(az identity show -g $RG -n $AGIC_MI_NAME --query clientId -o tsv)
echo $AGIC_MI_ID
echo $AGIC_MI_CLIENT_ID

# MI permissions
az role assignment create \
    --role "Contributor" \
    --assignee $AGIC_MI_CLIENT_ID \
    --scope $APPGW_RESOURCE_ID

###############
# AGIC on AKS #
###############

helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update