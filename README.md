# OpenShift pipelines p12n setup


### Prerequisites
* [rhpkg](https://gitlab.cee.redhat.com/tekton/team-docs/blob/master/productisation/PREREQUISITE.md)
* python 3.7+ and pip
* Get access to quay aplication repositories, so you can [test the OpenShift pipelines operator](#testing-opensift-pipelines-through-operator). Please use this [doc](https://docs.google.com/spreadsheets/d/1OyUtbu9aiAi3rfkappz5gcq5FjUbMQtJG4jZCNqVT20/edit#gid=0) or follow the [guide](https://mojo.redhat.com/docs/DOC-1202657). It might take day or some hours to get you an access.

## Customize your "workspace"

You can customize some element of this by using environment
variables. One use case would be to use `direnv` and have an `.envrc`
looking like the following:

```bash
export SCRIPT_DIR=${HOME}/src/gitlab.cee.redhat.com/hshinde/productize-pipelines
export WORKSPACE_DIR=${HOME}/src/p12n
export USER=vdemeest
```

### Setup 
* Execute `curl https://gist.githubusercontent.com/hrishin/90e7df87263c03801546ded814cd2947/raw/120f4004fe28dc61558daf29b3221cadc5e88f15/p12n-setup | bash`

or 

* Execute `git clone git@gitlab.cee.redhat.com:tekton/productize-pipelines.git $HOME/work/op-p12n/productize-pipelines`
* Then fire `./setup.sh`


## Config

* **[config.sh](./config.sh)**: 
  - This file holds the general configuration about cloning and sync the source code. `*_UPSTREAM_URL` and `*_UPSTREAM_BRANCH` holds upstream pipeline's, trigger's, operator's repo URL and branch to clone.
* **[image-config.yaml](./image-config.yaml)**: 
  - This file holds the configuration for building and mirroring images for pipelines, triggers, operators, operator's metadata and catalog components.
  - `replace`: This attribute determines how to generate `ENV` var for operator's container image, so images could be overriden as per the [operator configuration](https://github.com/openshift/tektoncd-pipeline-operator#override-images). Example 
     ```
     components:
      pipelines:
      - brew-package: openshift-pipelines-controller-rhel8-container
        name: pipelines-controller-rhel8
        replace: tekton-pipelines-controller
     ``` 
     `ENV` var gets generated here is like `PIPELINES_TEKTON_PIPELINES_CONTROLLER`. i.e. `<component name>_<replace>`
  - `brew-package`: Is used to fetch build info by package name
  - `dir`: Is the components directory. Used when bulding an image using `rhpkg`
  - `name`: Is used as image repo name while forming an image URL
  - `registry`: Used to deftimine image registry org while forming an image URL
  - `mirror`: In generel image mirroring configuration
  - `mirror.parallel`: Control's number of parallel mirroring jobs to execute


## Build Pipeline, Trigger, Operator images Flow Overview

<p align="center">
  <img width="100%" height="100%" src="image/build-flow.png">
</p>

1) **Sync source**: Sync source code(midstream) into pipelines, triggers and task catalog containers `dist-git` repositories(source code sync). Follow [Sync Source Code](#sync-source-code) section. (point 1)
2) **Test Container builds**: Start executing scratch containers build for all these repositories, to ensure all containers are getting build successfully. Follow [Test Containers Builds](#test-container-builds) section. (point 2)
3) **Build & Release Images**: Start executing containers build for all these repositories. Resultant container images get available at brew image registry. These images will be used for the actual release. Follow [Build Images](#build-release-images) section. (point 3)
4) **Publish the Operator**: Populate the operator CSV manifests to refer images built form the last step. Manifest is present `operator-metadata` `dist-git` repo. Then publish the Operator manifest(CSV & package) by building the metadata container. Follow [Publish Operator](#publish-operator) section. (point 4 and 5)


### Sync Source Code
```
make sync-source
```

### Test Container Builds
To test containers build, brew allows executing the scratch build where build artifacts get discarded after some time.

```
make test-image-builds
```

### Build Release Images
To build images that can be used for actual testing and release to stage, prod environment execute

```
make release-images
```

### Publish Operator
It refelcts latest container images URL into CSV file and publish the operator metadata to `pre-staging` env
```
make publish-operator
```

### Refelct Images SHA in operator CSV
If someone has already build images or you just want to reflect the image reference without building all images again, then invoke [Refelct Images SHA in operator CSV](#refelct-images-sha-in-operator-csv) target and [Publish Operator](#publish-operator) target.

```
make update-csv-image-ref
```

## Testing OpenSift Pipelines through Operator

### Prerequisite
1) Make sure you have access to any OpenShift 4 cluster and logged in as a `admin` user by `oc login` command
2) Create a namesapce definde as per the [.mirror.to-namespace](./image-config.yaml) config
3) Reflect the correct internal `OpenShift registry` URL in [.mirror.to-registry](./image-config.yaml) config. Execute `oc get route -n openshift-image-registry -o=jsonpath='{.items[0].spec.host}'` to get the registry URL
4) Log into `OpenShift registry` using `oc registry login --insecure=true`

### Flow
<p align="center">
  <img width="100%" height="100%" src="image/test-flow.png">
</p>

1) Make sure operator manifests are published to the quay application registry from previous build flow [steps (step-4. Publish Operator)](#publish-operator). If your intend is to test the operator then dont worry about this step, assume that developer has published an operator.  (point 1)

2) The operator manifests bundle is present in `quay.io` application repository which has limited access (check [Prerequisites](#prerequisites)). To access the operator metadata, a user needs to obtain the quay `token` and needs to create `secret` in the OpenShift cluster. (point 2)
    ```
    TOKEN=$(curl -sH "Content-Type: application/json" -XPOST https://quay.io/cnr/api/v1/users/login -d '
    {
      "user": {
        "username": "'"${QUAY_USERNAME}"'",
        "password": "'"${QUAY_TOKEN}"'"
      }
    }' | jq -r '.token')
    ```
    where the `QUAY_USERNAME` -> `rh-osbs-operators+<name>`, `QUAY_TOKEN` -> robot token recived in the encrypted email.

    Create a secret using Quay token

    ```
    oc create secret generic pre-stage-operators-secret --from-literal token="${TOKEN}" -n openshift-marketplace
    ```
3) All the images built while publishing an operator are in brew's registry which could be accessed over Red Hat VPN connection only. However, it's not possible/feasible to configure the OpenShift cluster to access the registry over the VPN connection. Hence we need to mirror those images from brew image registry(registry-proxy.engineering.redhat.com/rh-osbs) to OpenShift internal registry into `openshift-pipelines-10-tech-preview` namespace. Then create an `OperatorSource` resource in OpenShift cluster which points to the quay application registry and load the operator bundle. 
`OperatorHub` of OpenShift cluster refers to these bundles and enables the operator. Follow [Enable Operator](#enable-operator) section for all this. (point 3 and 4)
5) Subscribe to the `OpenShift Pipelines Operator` and it will spin up all pipelines resources in the OpenShift Cluster.

🎉 tada!

### Enable Operator
```
make enable-operator
```
