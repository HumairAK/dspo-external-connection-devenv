#!/usr/bin/env bash

usage() {
cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -u user -b bucket -d database [deploy|cleanup|generate]

> Note: user must have project admin in both minio_namespace AND mariadb_namespace, and be logged in via `oc login`.

Deploy MariaDB and Minio in OCP with exposed routes/hosts.
Secret and Access Key are auto generated.
Outputs a DataSciencePipelinesApplication cr with external credentials configured.

Arguments:
  deploy              requires: minio_namespace mariadb_namespace ngrok_token
  cleanup             requires: minio_namespace mariadb_namespace
  generate            requires: none
  minio_namespace     OCP Namespace to deploy external Minio.
  mariadb_namespace   OCP Namespace to deploy external MariaDB.
  ngrok_token         Your Ngrok token for mariadb tcp tunneling. Must be registered user, retrieve from: https://dashboard.ngrok.com/get-started/your-authtoken

Available options:

-h      Show this help.
-u      Use this user. (Default: testuser)
-b      Use this bucket. (Default: mlpipeline)
-d      Create database with this name. (Default: mlpipeline)

EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}


parse_args() {
  database="mlpipeline"
  user="testuser"
  bucket="mlpipeline"

  while getopts ":hd:u:sb:" options; do

    case "${options}" in
      h)
        usage
        ;;
      d)
        database="${OPTARG}"
        ;;
      u)
        user="${OPTARG}"
        ;;
      b)
        bucket="${OPTARG}"
        ;;
      :)
        echo "Error: -${OPTARG} requires an argument."
        die "Unknown option: ${OPTARG}"
        ;;
      *)
        die "Unknown option: ${OPTARG}" ;;
    esac

  done

  [[ -z "${database-}" ]] && die "Missing required parameter: database"
  return 0
}

keygen(){
  echo `openssl rand -base64 32`
}
passwordgen(){
  echo `< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32}`
}

deploy_minio(){
    echo "########################"
    echo "Deploying..Minio."
    echo "Minio Bucket to be used: ${bucket}"
    echo "Minio will be deployed in namespace: ${minio_namespace}"

    pushd manifests/minio > /dev/null
    var=$(passwordgen) yq '.stringData.accesskey = env(var)' secret.yaml | \
      var2=$(sleep 1s && passwordgen)  yq '.stringData.secretkey = env(var2)' | oc -n ${minio_namespace} apply -f -
    kustomize build . | oc -n ${minio_namespace} apply -f -
    popd > /dev/null
    echo "Finished deploying..Minio."
}

deploy_mariadb(){
  echo "########################"
  echo "Deploying..MariaDB..."
  echo "MariaDB Database: ${database}"
  echo "MariaDB User to be created: ${user}"
  echo "MariaDB will be deployed in namespace: ${mariadb_namespace}"

  pushd manifests/mariadb > /dev/null
  var=$(echo ${ngrok_token}) yq '.stringData.token = env(var)' secret.yaml | \
    var2=$(passwordgen) yq '.stringData.password = env(var2)' | \
    var3=$(passwordgen) yq '.stringData.rootpsw = env(var3)' | \
    var4=$(echo ${user}) yq '.stringData.username = env(var4)' | oc -n ${mariadb_namespace} apply -f -
  kustomize build . | oc -n ${mariadb_namespace} apply -f -
  popd > /dev/null
}

deploy(){
  msg="usage: ./devenv.sh deploy minio_namespace mariadb_namespace ngrok_token"
  [[ $# < 3 ]] && die "Missing script arguments ($msg)"
  [[ $# > 3 ]] && die "Too many script arguments ($msg)"
  minio_namespace=$1
  mariadb_namespace=$2
  ngrok_token=$3
  deploy_minio
  deploy_mariadb
}

generate(){
  echo "Generating manifests..."

  if [ ! -d "./output" ]; then
    mkdir output
  fi
  cp ./manifests/templates/* ./output/

  msg="usage: ./devenv.sh generate minio_namespace mariadb_namespace"
  [[ $# < 2 ]] && die "Missing script arguments ($msg)"
  [[ $# > 2 ]] && die "Too many script arguments ($msg)"
  minio_namespace=$1
  mariadb_namespace=$2
  BUCKET=$bucket

  echo "Fetching DB Pod"
  DB_POD=$(oc -n ${mariadb_namespace} get pod -l app=mariadb --no-headers | awk '{print $1}')
  oc -n ${mariadb_namespace} wait --for=condition=Ready pod/$DB_POD

  echo "Fetching DB host and port"
  MARIADBHOSTPORT=`oc -n ${mariadb_namespace} exec -c ngrok -ti $DB_POD -- curl -s localhost:4040/api/tunnels | jq .tunnels[0].public_url | grep tcp`
  DATABASE=$database
  DB_USER=$user

  IN=$(echo $MARIADBHOSTPORT | sed 's/tcp:\/\///g')
  IN=$(echo $IN | sed 's/\"//g')
  IFS=: read -r DB_HOST PORT <<< $IN
  echo Found [host: $DB_HOST] and [port: $PORT] for [pod: $DB_POD] in [namespace: ${mariadb_namespace}]

  oc -n ${mariadb_namespace} exec -c mariadb -ti $DB_POD -- mysql --user=root -e "DROP USER 'root'@'::1';" || true
  oc -n ${mariadb_namespace} exec -c mariadb -ti $DB_POD -- mysql --user=root -e "CREATE DATABASE ${DATABASE};" || true
  oc -n ${mariadb_namespace} exec -c mariadb -ti $DB_POD -- mysql --user=root -e "GRANT ALL PRIVILEGES ON ${DATABASE}.* TO '${DB_USER}'@'%';" || true

  DB_USER_PSW=$(oc -n ${mariadb_namespace} get secret ngrok-auth -o yaml | yq .data.password | base64 -d)
  echo connect to mariadb by entering the following:
  echo mariadb --host=${DB_HOST} --port=${PORT} --user=${DB_USER}  --password=${DB_USER_PSW}


  pushd ./output/ > /dev/null

  if [ ! -f "kustomization.yaml" ]; then
    kustomize init
  fi

  kustomize edit add resource db-secret.yaml dspa.yaml storage-secret.yaml

  # MariaDB Secret
  var=$(echo ${DB_USER_PSW}) yq -i '.stringData.customkey = env(var)' db-secret.yaml

  # Minio secret
  ACCESS_KEY=$(oc -n ${minio_namespace} get secret minio -o yaml | yq .data.accesskey | base64 -d)
  SECRET_KEY=$(oc -n ${minio_namespace} get secret minio -o yaml | yq .data.secretkey | base64 -d)
  var=$(echo ${ACCESS_KEY}) yq -i '.stringData.customaccessKey = env(var)' storage-secret.yaml
  var=$(echo ${SECRET_KEY}) yq -i '.stringData.customsecretKey = env(var)' storage-secret.yaml

  # Fill out DSPA CR
  var=$(echo ${DB_HOST}) yq -i '.spec.database.externalDB.host = env(var)' dspa.yaml
  var=$(echo ${DATABASE}) yq -i '.spec.database.externalDB.pipelineDBName = env(var)' dspa.yaml
  var=$(echo ${PORT}) yq -i '.spec.database.externalDB.port = strenv(var)' dspa.yaml
  var=$(echo ${DB_USER}) yq -i '.spec.database.externalDB.username = env(var)' dspa.yaml
  var=$(echo ${BUCKET}) yq -i '.spec.objectStorage.externalStorage.bucket = env(var)' dspa.yaml

  MINIO_HOST=$(oc -n ${minio_namespace} get route minio --template={{.spec.host}})
  var=$(echo ${MINIO_HOST}) yq -i '.spec.objectStorage.externalStorage.host = env(var)' dspa.yaml

  popd > /dev/null
}

cleanup(){
  echo "Cleaning up..."
  msg="usage: ./devenv.sh cleanup minio_namespace mariadb_namespace"
  [[ $# < 2 ]] && die "Missing script arguments ($msg)"
  [[ $# > 2 ]] && die "Too many script arguments ($msg)"
  minio_namespace=$1
  mariadb_namespace=$2

  echo "Cleaning up minio..."
  pushd manifests/minio > /dev/null
  oc -n ${minio_namespace} delete -f secret.yaml --ignore-not-found=true
  kustomize build . | oc -n ${minio_namespace} delete -f - --ignore-not-found=true
  popd > /dev/null
  echo "Done."

  echo "Cleaning up mariadb..."
  pushd manifests/mariadb > /dev/null
  oc -n ${mariadb_namespace} delete -f secret.yaml --ignore-not-found=true
  kustomize build . | oc -n ${mariadb_namespace} delete -f - --ignore-not-found=true
  popd > /dev/null
  echo "Done."
}

parse_args "$@"

shift $(( OPTIND - 1 ))
command=$1
case $command in
  generate)
    generate "${@:2}"
    ;;
  deploy)
    deploy "${@:2}"
    generate $2 $3
    ;;
  cleanup)
    cleanup "${@:2}"
    ;;
  *)
    echo "Unrecognized command [$commnad], exiting..."
    exit 1
esac