#!/bin/bash
set -x
oc patch operatorhub.config.openshift.io/cluster -p='{"spec":{"disableAllDefaultSources":true}}' --type=merge
oc delete opsrc redhat-operators -n openshift-marketplace --ignore-not-found
oc delete opsrc certified-operators -n openshift-marketplace --ignore-not-found
oc delete opsrc community-operators -n openshift-marketplace --ignore-not-found

oc delete -f operator-source.yaml --ignore-not-found
oc apply -f operator-source.yaml

oc adm policy add-cluster-role-to-user system:image-puller -z openshift-pipelines-operator -n openshift-operators

oc create ns openshift-pipelines
oc adm policy add-cluster-role-to-user system:image-puller -z tekton-pipelines-controller -n openshift-pipelines
oc adm policy add-cluster-role-to-user system:image-puller -z tekton-pipelines-webhook -n openshift-pipelines
oc adm policy add-cluster-role-to-user system:image-puller -z tekton-triggers-controller -n openshift-pipelines
