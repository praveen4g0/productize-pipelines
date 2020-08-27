#!/bin/bash
source config.sh
source helper.sh

# Check that this script is being run on linux. If not, exit 1.
os_check

OP_OPERATOR_META_WORKSPACE="${DIST_GIT_DIR}/openshift-pipelines-operator-prod-operator-metadata"

cd "${OP_OPERATOR_META_WORKSPACE}"

git add .

if output=$(git status --porcelain) && [ -n "$output" ]; then
  echo "Update image references in CSV" | \
  git commit -v -F -
else
  echo "No image reference changes to commit to the CSV"
fi

build ${OP_OPERATOR_META_WORKSPACE} ${OP_OPERATOR_METADATA_DIST_GIT_TAG}
