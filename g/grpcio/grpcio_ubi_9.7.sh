#!/bin/bash -e
# ----------------------------------------------------------------------------
# 
# Package       : grpcio
# Version       : v1.76.0
# Source repo   : https://github.com/grpc/grpc
# Tested on     : UBI:9.7
# Language      : Python
# Ci-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Viddya <Viddya@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

#variables
PACKAGE_NAME=grpcio
PACKAGE_VERSION=${1:-v1.76.0}
PACKAGE_URL=https://github.com/grpc/grpc

#clone repository
git clone -b ${PACKAGE_VERSION} --depth 1 $PACKAGE_URL
cd grpc

# Build grpcio wheel and install dependencies
git submodule update --init
python -m pip install -r requirements.txt
python -m pip install --upgrade setuptools
python -m pip install "cython==3.1.1"
export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true

#install
if ! (GRPC_PYTHON_BUILD_WITH_CYTHON=1 python -m pip wheel . -w ./dist --no-build-isolation && python -m pip install ./dist/*.whl) ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

echo "------------------$PACKAGE_NAME:Install_success-------------------------"
python -m pip list | grep grpc

#test
PYTHON_VERSION=$(python3 -V 2>&1 | awk '{split($2,a,"."); print a[1]"."a[2]}')

# Install the required dependencies and modules to run tests
pip install "opentelemetry-api>=1.21.0" "opentelemetry-sdk>=1.25.0" "opentelemetry-resourcedetector-gcp>=1.6.0a0" "oauth2client>=1.4.7" "setuptools==70.1.1" "zope-event<5.0" --extra-index-url https://pypi.org/simple
./tools/distrib/install_all_python_modules.sh

# Create local bin dir and symlink to the chosen Python binary
PY_DIR="py${PYTHON_VERSION/./}"
mkdir -p $PY_DIR/bin
ln -sf "$(which python3)" $PY_DIR/bin/python

# Extract version info and paths
VENV_PATH=$(python3 -c "import sys; print(sys.prefix)")
SITE_PACKAGES="$VENV_PATH/lib/python$PYTHON_VERSION/site-packages"

# Export environment variables
export VIRTUAL_ENV="$VENV_PATH"
export PYTHONPATH="$SITE_PACKAGES:$PYTHONPATH"

# Run the tests with the selected Python version
if ! (tools/run_tests/run_tests.py -l python -c dbg --compiler python$PYTHON_VERSION) ; then
    echo "------------------$PACKAGE_NAME:Install_success_but_test_fails---------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_success_but_test_Fails"
    exit 2
else
    echo "------------------$PACKAGE_NAME:Install_&_test_both_success-------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub  | Pass |  Both_Install_and_Test_Success"
    exit 0
fi
