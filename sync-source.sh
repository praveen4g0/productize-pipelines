#!/bin/bash

source config.sh
source helper.sh

# Check that this script is being run on linux. If not, exit 1.
os_check

function sync_components_source() {
  local upstream_repo=$1
  local upstream_branch=$2
  local upstream_repo_name=$3
  local dist_git_repo=$4
  local dist_git_branch=$5
  local dist_git_repo_prefix=$6
  local dist_git_components=$7
  local ignore_components_sync=$8
 
  OP_UPSTREAM_WORKSPACE=${UPSTREAM_DIR}/${upstream_repo_name}
  print_line
  echo "Fetching upstream ${OP_UPSTREAM_WORKSPACE}"
  print_line
  UPSTREAM_COMMIT=$(clone_repo "${OP_UPSTREAM_WORKSPACE}" "${upstream_repo}" "${upstream_branch}")
  
  for IMAGE in ${dist_git_components}
  do
    OP_DIST_GIT_WORKSPACE=${DIST_GIT_DIR}/${dist_git_repo_prefix}${IMAGE}
    print_line
    echo "Sync ${dist_git_repo_prefix}${IMAGE}"
    print_line
    
    echo "Cloning ${OP_DIST_GIT_URL}/${dist_git_repo_prefix}${IMAGE}"
    clone_repo "${OP_DIST_GIT_WORKSPACE}" "${OP_DIST_GIT_URL}/${dist_git_repo_prefix}${IMAGE}" "${dist_git_branch}"

    if [ ! -d "${OP_DIST_GIT_WORKSPACE}" ]; then
      echo "Directory ${OP_DIST_GIT_WORKSPACE} does not exist! Aborting!"
      exit 1
    fi

    if [[ " ${ignore_components_sync[@]} " =~ " ${IMAGE} " ]]; then
      echo "Ignoring sync for ${OP_DIST_GIT_WORKSPACE}" 
      continue
    fi

    echo "Starting sync for ${OP_DIST_GIT_WORKSPACE}"
    #Does dist-git repo already have the latest upstream? If yes.. no need to sync.
    DISTGIT_COMMIT=$(git -C "${OP_DIST_GIT_WORKSPACE}" log | grep "Using commit" | head -1 | awk '/Using commit/ { print $3 }')
    if [ "${UPSTREAM_COMMIT}" == "${DISTGIT_COMMIT}" ]; then
      echo "${OP_DIST_GIT_WORKSPACE} repo is already synced"
    else 
      echo "Syncing files..."
      rsync -a \
        --delete-before \
        --exclude-from "${SCRIPT_DIR}"/operand.exclude \
        "${OP_UPSTREAM_WORKSPACE}"/ \
        "${OP_DIST_GIT_WORKSPACE}"/
    fi

    local dirty=false
    # Commit the changes
    cd "${OP_DIST_GIT_WORKSPACE}"

    git add .
    if local output=$(git status --porcelain) && [ -z "$output" ]; then
      echo "No changes to commit..."
    else
      echo "Import latest from upstream ${upstream_branch}

Using commit ${UPSTREAM_COMMIT}
from ${upstream_repo}, branch ${upstream_branch}" | \
      git commit -F -
      dirty=true
    fi

    if commits_to_push; then
      echo "Pending some commits on local repository"
      dirty=true
    fi

    if ! ${push_enabled}; then
      echo "Skipping git push..."
      continue
    fi

    if ${dirty}; then
      echo "Pushing the commits/changes for ${OP_DIST_GIT_WORKSPACE}..."
      rhpkg push
      echo "Sync (commit && push) for ${IMAGE} is completed \o/"
    else 
      echo "Repository is clean, no changes needed"
    fi
      
    print_line
  done
}

if [ "$1" == "metasync" ]; then
  print_line
  echo "Fetching operator metadata"
  print_line
  OP_OPERATOR_META_WORKSPACE="${DIST_GIT_DIR}/openshift-pipelines-operator-prod-operator-metadata"
  clone_repo "${OP_OPERATOR_META_WORKSPACE}" "${OP_DIST_GIT_URL}/openshift-pipelines-operator-prod-operator-metadata" "${OP_OPERATOR_METADATA_DIST_GIT_BRANCH}"

  exit 0
fi

# sync pipelines repo
PIPELINE_COMPONENTS=("controller webhook bash creds-init entrypoint gcs-fetcher git-init gsutil imagedigestexporter kubeconfigwriter nop pullrequest-init")
IGNORE_IMAGE_SYNC=("nop gsutil")
sync_components_source "${OP_UPSTREAM_URL}" "${OP_UPSTREAM_BRANCH}" "pipelines" "${OP_DIST_GIT_URL}" "${OP_DIST_GIT_BRANCH}" "openshift-pipelines-" "${PIPELINE_COMPONENTS}" "${IGNORE_IMAGE_SYNC}"

# sync triggers repo
TRIGGERS_COMPONENTS=("controller webhook eventlistenersink")
sync_components_source "${OPT_UPSTREAM_URL}" "${OPT_UPSTREAM_BRANCH}" "triggers" "${OP_DIST_GIT_URL}" "${OP_DIST_GIT_BRANCH}" "openshift-pipelines-triggers-" "${TRIGGERS_COMPONENTS}"

# sync operator repo
OPERATOR_COMPONENTS=("operator")
sync_components_source "${OPO_UPSTREAM_URL}" "${OPO_UPSTREAM_BRANCH}" "operator" "${OP_DIST_GIT_URL}" "${OP_DIST_GIT_BRANCH}" "openshift-pipelines-" "${OPERATOR_COMPONENTS}"

print_line
echo "Cloning buildah image"
print_line
BUILDAH_WORKSPACE="${DIST_GIT_DIR}/openshift-pipelines-catalog-buildah"
clone_repo "${BUILDAH_WORKSPACE}" "${OP_DIST_GIT_URL}/openshift-pipelines-catalog-buildah" "${OP_DIST_GIT_BRANCH}"

print_line
echo "Cloning operator metdata"
print_line
OP_OPERATOR_META_WORKSPACE="${DIST_GIT_DIR}/openshift-pipelines-operator-prod-operator-metadata"
clone_repo "${OP_OPERATOR_META_WORKSPACE}" "${OP_DIST_GIT_URL}/openshift-pipelines-operator-prod-operator-metadata" "${OP_OPERATOR_METADATA_DIST_GIT_BRANCH}"
