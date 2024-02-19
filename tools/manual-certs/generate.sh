#!/usr/bin/env bash

path="${1:-"."}"

# Create Key and CSR
openssl req -newkey rsa:4096 -nodes -keyout ${path}/domain.key -out ${path}/domain.csr -subj "/C=XX/CN=*.tcp.ngrok.io"

# Creating a CA-Signed Certificate With Our Own CA

# Create a Self-Signed Root CA
openssl req \
  -x509 -sha256 \
  -days 3650 \
  -newkey rsa:4096 \
  -keyout ${path}/rootCA.key \
  -nodes \
  -out ${path}/rootCA.crt \
  -subj "/C=XX/CN=rh-dsp-devs.io"

# Sign Our CSR With Root CA
# As a result, the CA-signed certificate will be in the domain.crt file.
openssl x509 -req -days 3650 -CA ${path}/rootCA.crt -CAkey ${path}/rootCA.key -in ${path}/domain.csr -out ${path}/domain.crt -CAcreateserial -extfile domain.ext