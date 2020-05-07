#!/usr/bin/env bash
# This script is there to be executed once you have a cluster available

set -euo pipefail

TOKEN=${TOKEN:-}
test -z "${TOKEN}" && {
    echo "TOKEN env variable is required"
    exit 1
}

echo "Enable registry defaultRoute"
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
sleep 5

ROUTE=$(oc get route -n openshift-image-registry -o=jsonpath='{.items[0].spec.host}')

echo "Login to registry"
oc registry login --insecure=true

echo "Create openshift-pipelines-tech-preview namespace"
oc create ns openshift-pipelines-tech-preview || true

echo "Create pre-stage-operators-secret"
oc create secret generic pre-stage-operators-secret --from-literal token="${TOKEN}" -n openshift-marketplace || true

echo "Backup image-config.yaml"
cp image-config.yaml image-config.yaml.bak
sed -i "s@default-route-openshift-image-registry.apps-crc.testing@${ROUTE}@g" image-config.yaml

echo "Enable operator"
make enable-operator

echo "Restore image-config.yaml"
cp image-config.yaml.bak image-config.yaml
