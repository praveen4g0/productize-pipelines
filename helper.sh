#!/bin/bash

function os_check() {
  if [[ $(uname -s) != Linux ]]; then
    echo "You must run this script on a Fedora host that has the python koji package installed."
    exit 1
  fi
}

function change_dir_or_exit() {
  local dir=$1
  if [ -d "${dir}" ]; then
    cd "${dir}"
  else
    echo "${dir} does not exist"
    exit 1
  fi
}

function remove_dir_or_exit() {
  local dir=$1
  if [ -d "${dir}" ]; then
    rm -rf "${dir}"
  else
    echo "Directory '${dir}' does not exist"
    exit 1
  fi
}

function clone_repo() {
  local workspace=$1
  local url=$2
  local branch=$3
  local lcd=$(pwd)

  if [[ -d ${workspace} ]]
  then
    cd ${workspace}
    git merge --allow-unrelated-histories --no-edit origin/${branch}
  else
    git clone ${url} --branch ${branch} --single-branch ${workspace}
  fi

  cd ${workspace}
  local commit=$(git rev-parse HEAD)
  cd ${lcd}

  echo ${commit}
}

function commits_to_push() {
  if local cherry=$(git cherry -v); then
    if [[ -n "${cherry}" ]]; then
      return 0
    fi
  fi

  return 1
}

function remove_repo_if_clean() {
  local directory=$1
  if [ -d ${directory} ]; then
    if output=$(git -C "${directory}" status --porcelain) && [ -z "$output" ]; then
      rm -rf ${directory}
    else
      echo "Cannot remove ${directory} because it has uncommitted changes..."
      exit 1
    fi
  fi
}

function build() {
  local directory=$1

  echo "Attempting to build in ${directory}."

  if commits_to_push; then

    if ! ${push_enabled}; then
      echo ""
      echo "There are some commits to push, however git push is currently disabled."
      echo "To enable, set push_enabled=true in config.sh."
      echo ""
      echo "Aborting!"
      return 1;
    fi

    echo "Pushing commits in ${directory}"
    rhpkg push

    if ${build_enabled}; then
      echo "Building in ${directory}"
      rhpkg container-build
    fi
  else
    if ${force_build_enabled}; then
      echo "No new commits. Forcing build!"
      echo "To disable forced builds, set force_build_enable=false in config.sh"
      rhpkg container-build
    else
      echo "No new commits. Skipping build!"
      echo "To force build, set force_build_enable=true in config.sh"
    fi
  fi
}
