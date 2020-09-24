#!/usr/bin/env bash
# This script is there to be executed once you have a cluster available

#PREREQ
# while working with stagging
# get access to registry.stage.redhat.io by accessing
# https://access.stage.redhat.com/

set -euo pipefail

echo CSV_VERSION: $CSV_VERSION

TOKEN=${TOKEN:-}
test -z "${TOKEN}" && {
    echo "TOKEN env variable is required"
    exit 1
}

function reset_manifests() {
  echo "Restore image-config.yaml"
  cp image-config.yaml.bk image-config.yaml || true
  echo "Restore operator-source.yaml"
  cp operator-source.yaml.bk operator-source.yaml || true
}

ENVSTAGE="stage"
ENVPRESTAGE="pre-stage"
STAGGING_REGISTRY="registry.stage.redhat.io"

echo "Enable registry defaultRoute"
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
while true; do
  sleep 3
  oc get route default-route -n openshift-image-registry > /dev/null 2>&1 && break
done

ROUTE=$(oc get route -n openshift-image-registry -o=jsonpath='{.items[0].spec.host}')

echo "Login to on cluster registry"
oc registry login --insecure=true

echo "Create openshift-pipelines-tech-preview namespace"
oc create ns openshift-pipelines-tech-preview || true

echo "Create operators-source-pull-secret for ENVIRONMENT=${ENVIRONMENT}"
oc create secret generic operators-source-pull-secret --from-literal token="${TOKEN}" -n openshift-marketplace || true

echo "Backup image-config.yaml"
cp image-config.yaml image-config.yaml.bk
trap reset_manifests ERR EXIT

sed  -i "s@\(to-registry:\ \).*@\1${ROUTE}@" image-config.yaml

if [[ ${ENVIRONMENT} = ${ENVSTAGE} ]]; then
  echo "Login to on stagging registry"
  oc registry login --registry registry.stage.redhat.io --auth-basic="${STAGE_USER}:${STAGE_PASS}" --insecure=true
  sed  -i -e "s@\(from-registry:\ \).*@\1${STAGGING_REGISTRY}@" \
          -e "s@\(from-org:\ \).*@\1openshift-pipelines-tech-preview@" \
          -e "s@\(from-image-prefix:\ \).*@\1''@" image-config.yaml

  cp operator-source.yaml operator-source.yaml.bk
  sed  -i -e "s@\(name:\ \).*@\1stage-operators@" \
          -e "s@\(registryNamespace:\ \).*@\1redhat-operators-stage@" operator-source.yaml

  oc adm policy add-cluster-role-to-user registry-viewer system:anonymous
  ./hack/add-machine-config.sh
fi

echo "Enable operator"
make enable-operator
