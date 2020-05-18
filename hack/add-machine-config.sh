#!/usr/bin/env bash

# setup MachineConfig resource in Master and Worker nodes
# to facilitate redirection of image url from:
# prefix = "registry.stage.redhat.io"
# to:
# location = "image-registry.openshift-image-registry.svc:5000"
for mt in worker master; do
    MACHINE_TYPE=$mt BASE64_CONTENT=$(base64 hack/registries.conf -w0) envsubst < hack/registry-mirror-template.yaml  | oc apply -f -
done
