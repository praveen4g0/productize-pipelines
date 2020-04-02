#!/bin/bash

source config.sh
source helper.sh

print_line
echo "Cloning p12n script to ${SCRIPT_DIR}"
print_line
git clone git@gitlab.cee.redhat.com:tekton/productize-pipelines.git $SCRIPT_DIR

cd $SCRIPT_DIR

print_line
echo "Installing prerequisites"
print_line
sudo dnf install -y gcc python-devel krb5-devel krb5-workstation python-devel
sudo pip install -r requirements.txt

print_line
echo "Setup is done, execute 'cd ${SCRIPT_DIR}' to begin productization"
print_line
