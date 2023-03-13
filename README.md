# DSPO External conneciton devenv

Deploy an external MariaDB (via tunneling) and Minio (via ocp Route). 

NOT FOR PRODUCTION!

### Pre-reqs:
* yq
* oc
* kustomize

You need to be a **registered** ngrok user to tunnel tcp connections.

https://dashboard.ngrok.com/get-started/your-authtoken
Retrieve the **token** and execute the following on the repo: 

```bash
oc new-project minio-external
oc new-project mariadb-external
git clone https://github.com/HumairAK/dspo-external-connection-devenv.git
cd dspo-external-connection-devenv
./devenv.sh deploy minio-external mariadb-external ${ADD_YOUR_NGROK_TOKEN_HERE}

# Or provide your own options instead of the defaults
# ./devenv.sh -u myuser -d mydatabase deploy minio-external mariadb-external
```

Once the pods in both namespaces are READY then run the following: 
```bash
./devenv.sh generate minio-external mariadb-external

# deploy the dspa + secrets in a namespace: 
cd output
oc new-project ds-project
kustomize build . | oc -n ds-project apply -f -
```


# Cleanup

```bash
oc new-project minio-external
oc new-project mariadb-external
git clone https://github.com/HumairAK/dspo-external-connection-devenv.git
cd dspo-external-connection-devenv
./devenv.sh deploy minio-external mariadb-external ${ADD_YOUR_NGROK_TOKEN_HERE}
```
```bash
./devenv.sh cleanup minio-external mariadb-external
```
