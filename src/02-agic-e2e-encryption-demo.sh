mkdir agic-setup
cd agic-setup
openssl ecparam -out frontend.key -name prime256v1 -genkey
openssl req -new -sha256 -key frontend.key -out frontend.csr -subj "/CN=frontend"
openssl x509 -req -sha256 -days 365 -in frontend.csr -signkey frontend.key -out frontend.crt

openssl ecparam -out backend.key -name prime256v1 -genkey
openssl req -new -sha256 -key backend.key -out backend.csr -subj "/CN=backend"
openssl x509 -req -sha256 -days 365 -in backend.csr -signkey backend.key -out backend.crt

kubectl create secret tls frontend-tls --key="frontend.key" --cert="frontend.crt"
kubectl create secret tls backend-tls --key="backend.key" --cert="backend.crt"

kubectl get secrets

kubectl apply -f ../agic-app.yaml


az network application-gateway root-cert create \
    --gateway-name $APPGW  \
    --resource-group $RG \
    --name backend-tls \
    --cert-file backend.crt

cat << EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: website-ingress
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    appgw.ingress.kubernetes.io/backend-protocol: "https"
    appgw.ingress.kubernetes.io/backend-hostname: "backend"
    appgw.ingress.kubernetes.io/appgw-trusted-root-certificate: "backend-tls"
spec:
  tls:
    - secretName: frontend-tls
      hosts:
        - agic-demo.az.mohamedsaif.com
  rules:
    - host: agic-demo.az.mohamedsaif.com
      http:
        paths:
        - path: /
          backend:
            serviceName: website-service
            servicePort: 8443
EOF

kubectl get ingress

# Testing the deployed pod on https:8443
kubectl exec -it website-deployment-REPLACE -- curl -k https://localhost:8443