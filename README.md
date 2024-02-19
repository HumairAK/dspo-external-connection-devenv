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
# deploy the dspa + secrets in a namespace: 
cd output
oc new-project ds-project
kustomize build . | oc -n ds-project apply -f -
```

# Deploy TLS enabled minio/mariadb

Same thing but add the `-t` flag to enable tls deployment: 

```
./devenv.sh -t deploy minio mariadb $ngrok_token
```

Confirm tls is enabled in minio by visiting the minio concel route and inspecting the certs there.
For mariadb, login to mariadb and use the GLOBAL VARIABLES statement to confirm tls enablement: 

```
mariadb --host=0.tcp.ngrok.io --port=17221 --user=testuser --password=<omited>

Welcome to the MariaDB monitor.  Commands end with ; or \g.
Your MariaDB connection id is 12
Server version: 10.3.35-MariaDB MariaDB Server

Copyright (c) 2000, 2018, Oracle, MariaDB Corporation Ab and others.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

MariaDB [(none)]> SHOW GLOBAL VARIABLES LIKE 'have_ssl';
+---------------+-------+
| Variable_name | Value |
+---------------+-------+
| have_ssl      | YES   |
+---------------+-------+
1 row in set (0.042 sec)

```

Add a configmap "odh-trusted-ca-bundle" to the DSPA's namespace and in it's `.data` field add the contents of: `output/certs/rootCA.crt` 
combined with the contents of `kube-root-ca.crt` (find this configmap in the DSPA's namespace). 


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
