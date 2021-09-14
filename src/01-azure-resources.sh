##############
# Parameters #
##############

# General
PREFIX=agic-dev
LOCATION=westeurope
RG=$PREFIX-rg

# Network
VNET=$PREFIX-vnet
VNET_CIDR=10.170.0.0/23
AKS_SUBNET=aks
AKS_SUBNET_CIDR=10.170.0.0/24
APPGW_SUBNET=appgw
APPGW_SUBNET_CIDR=10.170.1.0/28
PE_SUBNET=private-endpoints
PE_SUBNET_CIDR=10.170.16.0/28

# Key Vault
KEYVAULT=$PREFIX-kv

# App Gateway
APPGW=$PREFIX-appgw

# AKS
AKS=$PREFIX-aks

##################
# Resource Group #
##################


###################
# Virtual Network #
###################



#############
# Key Vault #
#############



###############
# App Gateway #
###############


#######
# AKS #
#######
