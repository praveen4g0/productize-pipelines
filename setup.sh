#!/bin/bash

source config.sh

echo "----------------------------------------------------------------------------"
echo "Cloning p12n script to ${SCRIPT_DIR}"
echo "----------------------------------------------------------------------------"
git clone git@gitlab.cee.redhat.com:hshinde/productize-svls.git $SCRIPT_DIR

cd $SCRIPT_DIR

echo "----------------------------------------------------------------------------"
echo "Installing prerequisites"
echo "----------------------------------------------------------------------------"
sudo dnf install -y gcc python-devel krb5-devel krb5-workstation python-devel
sudo pip install -r requirements.txt

echo "----------------------------------------------------------------------------"
echo "Setup is done, execute 'cd ${SCRIPT_DIR}' to begin productization"
echo "----------------------------------------------------------------------------"
