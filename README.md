# OpenShift pipelines p12n setup


## Prerequisites
* [rhpkg](https://gitlab.cee.redhat.com/tekton/team-docs/blob/master/productisation/PREREQUISITE.md) (not needed if you're just testing the operator)
* python 3.7+ and pip
* Get access to quay aplication repositories, so you can [test the OpenShift pipelines operator](#testing-opensift-pipelines-through-operator). Please use this [doc](https://docs.google.com/spreadsheets/d/1OyUtbu9aiAi3rfkappz5gcq5FjUbMQtJG4jZCNqVT20/edit#gid=0) or follow the [guide](https://mojo.redhat.com/docs/DOC-1202657). It might take day or some hours to get you an access.


## Setup
* Execute `curl https://gist.githubusercontent.com/hrishin/90e7df87263c03801546ded814cd2947/raw/120f4004fe28dc61558daf29b3221cadc5e88f15/p12n-setup | bash`.
It will clone the repo to `$HOME/work/op-p12n/productize-pipelines`, installs the required script dependencies(python packages and RPMS)

or

* Execute `git clone git@gitlab.cee.redhat.com:tekton/productize-pipelines.git $HOME/work/op-p12n/productize-pipelines`
* Then fire `./setup.sh` to install the required script dependencies(python packages and RPMS)
* You could set envionment variables to [customize your workspace](#customize-your-"workspace")


#### Customize your "workspace"

You can customize some element of this by using environment
variables. One use case would be to use `direnv` and have an `.envrc`
looking like the following:

```bash
export SCRIPT_DIR=${HOME}/src/gitlab.cee.redhat.com/tekton/productize-pipelines
export WORKSPACE_DIR=${HOME}/src/p12n
export USER=vdemeest
# For QUAY
export QUAY_USERNAME=rh-osbs-operators+${USER}
export QUAY_TOKEN=%REDACTED%
export TOKEN=$(curl -sH "Content-Type: application/json" -XPOST https://quay.io/cnr/api/v1/users/login -d '
{
  "user": {
    "username": "'"${QUAY_USERNAME}"'",
    "password": "'"${QUAY_TOKEN}"'"
  }
}' | jq -r '.token')
```

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
  - `mirror.retry`: Defines number of retry attempts if image mirroring fails


## Build Pipeline, Trigger, Operator images Flow Overview

<p align="center">
  <img width="100%" height="100%" src="image/build-flow.png">
</p>

1) **Sync source**: Sync source code(midstream) into pipelines, triggers and task catalog containers `dist-git` repositories(source code sync). Follow [Sync Source Code](#sync-source-code) section.
Just ensure that [config.sh](./config.sh) has the right upstream/midstream branch names (point 1)
2) **Test Container builds**: Start executing scratch containers build for all these repositories, to ensure all containers are getting build successfully. Follow [Test Containers Builds](#test-container-builds) section. (point 2)
3) **Build & Release Images**: Start executing containers build for all these repositories. Resultant container images get available at brew image registry. These images will be used for the actual release. Follow [Build Images](#build-release-images) section. (point 3)
4) **Publish the Operator**: Populate the operator CSV manifests to refer images built form the last step. Manifest is present `operator-metadata` `dist-git` repo. Then publish the Operator manifest(CSV & package) by building the metadata container. Follow [Publish Operator](#publish-operator) section. (point 4 and 5)


#### Sync Source Code
```
make sync-source
```

#### Test Container Builds
To test containers build, brew allows executing the scratch build where build artifacts get discarded after some time.

```
make test-image-builds
```

#### Build Release Images
To build images that can be used for actual testing and release to stage, prod environment execute

```
make release-images
```


#### Create new CSV file (if required)

Each new release of the operator is packaged as a CluserServiceVersion (CSV file). If a CSV file does not exist for 
the current release target version, then create on using the `make new-csv` target.

**Note:** The new CSV file will have all image references reset to `<new image>`

eg:
```
CSV_VERSION=1.1.0-rc1 FROM_CSV_VERSION=1.0.1 OPERATOR_CHANNEL_NAME=preview make new-csv
```

#### Refelct Images SHA in operator CSV

After Images are built, we need to update them in the CSV file.

```
CSV_VERSION=1.1.0-rc1 make update-csv-image-ref
```

#### Publish Operator
It reflects latest container images URL into CSV file and publish the operator metadata to `pre-staging` env
(builds and pushes the operator metadata image)

```
CSV_VERSION=1.1.0-rc1 make publish-operator
```


## Testing OpenSift Pipelines through Operator
**Note: As of now this could work for Linux host only**
### Prerequisite
1) Make sure all [prerequisites](#prerequisites) are in place (except `rhpkg`) and [setup](#setup) is done correctly.
2) [Kerberos setup](https://gitlab.cee.redhat.com/tekton/team-docs/blob/master/productisation/PREREQUISITE.md#setup) is done and SSO is working by executing `$ kinit && klist`. (Needs VPN connection)
3) Make sure you have access to any OpenShift 4 cluster and logged in as a `admin` user by `oc login` command. Please also make sure, `oc` binary is up to the date
4) Create a namesapce definde as per the [.mirror.to-namespace](./image-config.yaml) config. e.g. `oc create ns openshift-pipelines-tech-preview`
5) Reflect the correct internal `OpenShift registry` URL in [.mirror.to-registry](./image-config.yaml) config. Execute `oc get route -n openshift-image-registry -o=jsonpath='{.items[0].spec.host}'` to get the registry URL. If it's not exposed, run `oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge`
6) Log into `OpenShift registry` using `oc registry login --insecure=true`
7) while working witn stagging, make sure you have access to registry.stage.redhat.io by registering at https://access.stage.redhat.com
8) set following environment variables
   - ENVIRONMENT : `pre-stage` for pre-stagging, `stage` for stagging
   - STAGE_USER : (while working with stagging only) username for https://access.stage.redhat.com
   - STAGE_PASS : (while working with stagging only) password for https://access.stage.redhat.com

### Flow

```
shortcut: perform step 2 below (create token), then set relevant enviroment variables specified in above section and run `./install-productized-operator.sh`
```
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
    oc create secret generic operators-source-pull-secret --from-literal token="${TOKEN}" -n openshift-marketplace
    ```
3) All the images built while publishing an operator are in brew's registry which could be accessed over Red Hat VPN connection only. However, it's not possible/feasible to configure the OpenShift cluster to access the registry over the VPN connection. Hence we need to mirror those images from brew image registry(registry-proxy.engineering.redhat.com/rh-osbs) to OpenShift internal registry into `openshift-pipelines-tech-preview` namespace. Then create an `OperatorSource` resource in OpenShift cluster which points to the quay application registry and load the operator bundle.
`OperatorHub` of OpenShift cluster refers to these bundles and enables the operator. Follow [Enable Operator](#enable-operator) section for all this. (point 3 and 4)
5) Subscribe to the `OpenShift Pipelines Operator` and it will spin up all pipelines resources in the OpenShift Cluster.

🎉 tada!

You can use `./install-productized-operator.sh` if you are using
`direnv` and a `.envrc`, *or* setuping the required environment
variable prior to execute the script:

- `USER`
- `QUAY_USERNAME`
- `QUAY_TOKEN`
- `TOKEN`
- `ENVIRONMENT` (`pre-stage` or `stage`)

then;

```shell script
CSV_VERSION=1.1.0-rc1 ./install-productized-operator.sh
```

You also need to ensure you did log in to your cluster before running
the script (`oc login …`).

#### Enable Operator
```
make enable-operator
```
