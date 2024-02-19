#!/usr/bin/env bash

#openssl req \
#  -x509 \
#  -sha256 \
#  -newkey rsa:4096 \
#  -keyout key.pem \
#  -out cert.pem \
#  -days 3650 \
#  -nodes \
#  -subj "/C=XX/CN=0.tcp.ngrok.io" \
#  -addext "subjectAltName = DNS:mariadb.mariadb.svc,mariadb.mariadb.svc.cluster.local,localhost"


# Create Key and CSR
openssl req -newkey rsa:4096 -nodes -keyout domain.key -out domain.csr -subj "/C=XX/CN=0.tcp.ngrok.io"

# Creating a CA-Signed Certificate With Our Own CA

# Create a Self-Signed Root CA
openssl req \
  -x509 -sha256 \
  -days 3650 \
  -newkey rsa:4096 \
  -keyout rootCA.key \
  -nodes \
  -out rootCA.crt \
  -subj "/C=XX/CN=0.tcp.ngrok.io"

# Sign Our CSR With Root CA
# As a result, the CA-signed certificate will be in the domain.crt file.
openssl x509 -req -days 3650 -CA rootCA.crt -CAkey rootCA.key -in domain.csr -out domain.crt -CAcreateserial -extfile domain.ext