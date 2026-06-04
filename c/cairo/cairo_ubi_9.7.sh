#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# 
# Package       : cairo
# Version       : 1.16.0
# Source repo   : https://gitlab.freedesktop.org/cairo/cairo.git
# Tested on     : UBI:9.7
# Language      : C/C++
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer    : Viddya <viddya@ibm.com>
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -euo pipefail

# Variables
PACKAGE_NAME=cairo
PACKAGE_VERSION=${1:-1.16.0}
PACKAGE_URL=https://gitlab.freedesktop.org/cairo/cairo.git
PKG_NAME=${PKG_NAME:-cairo}
PKG_VERSION=${PKG_VERSION:-$PACKAGE_VERSION}

# Initialize paths
ROOT_DIR="$(pwd)"
BUILD_DIR="$ROOT_DIR/$PACKAGE_NAME"
INSTALL_DIR="$ROOT_DIR/install/$PKG_NAME/$PKG_NAME/wheel_payload"
PKG_DIR="$ROOT_DIR/install/$PKG_NAME"
VENV_DIR="$PKG_DIR/virtualEnv"

echo "Cleaning previous install directories..."
rm -rf "$INSTALL_DIR" "$BUILD_DIR"

# Install system dependencies for UBI 9.7
# dnf config-manager --add-repo https://mirror.stream.centos.org/9-stream/AppStream/s390x/os/
# dnf config-manager --add-repo https://mirror.stream.centos.org/9-stream/BaseOS/s390x/os/
# dnf config-manager --add-repo https://mirror.stream.centos.org/9-stream/CRB/s390x/os/
# wget http://mirror.centos.org/centos/RPM-GPG-KEY-CentOS-Official
# mv RPM-GPG-KEY-CentOS-Official /etc/pki/rpm-gpg/.
# rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official
# dnf install --nodocs -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

# Install dependencies and tools
yum install -y gcc gcc-c++ make autoconf automake libtool pkg-config \
    python3 python3-pip python3-devel git \
    zlib-devel libpng-devel freetype-devel fontconfig-devel \
    glib2-devel binutils-devel wget

# Clone repository
git clone $PACKAGE_URL
cd $BUILD_DIR
git checkout $PACKAGE_VERSION

# Create Python package structure
mkdir -p "$PKG_DIR/$PKG_NAME"
touch "$PKG_DIR/$PKG_NAME/__init__.py"

# Copy licenses
cp $BUILD_DIR/COPYING* $PKG_DIR/ 2>/dev/null || true

# Generate setup.py
cat > "$PKG_DIR/setup.py" <<EOF
from setuptools import setup, find_packages
from setuptools.command.install import install
import os
from shutil import copytree

class InstallWithLibs(install):
    def run(self):
        install.run(self)
        src = os.path.join(os.path.dirname(__file__), "${PKG_NAME}")
        dst = os.path.join(self.install_lib, "${PKG_NAME}")
        copytree(src, dst, dirs_exist_ok=True)

setup(
    name="${PKG_NAME}",
    version="${PKG_VERSION}",
    packages=find_packages(),
    include_package_data=True,
    cmdclass={"install": InstallWithLibs},
)
EOF

# Generate pyproject.toml
cat > "$PKG_DIR/pyproject.toml" <<EOF
[build-system]
requires = ["setuptools", "wheel"]
build-backend = "setuptools.build_meta"
EOF

# Generate MANIFEST.in
cat > "$PKG_DIR/MANIFEST.in" <<EOF
recursive-include ${PKG_NAME}/wheel_payload *
EOF

# Create Python virtual environment
cd "$PKG_DIR"
python3 -m venv virtualEnv
source "virtualEnv/bin/activate"

# Install build tools
pip install --upgrade pip setuptools wheel build --extra-index-url https://pypi.org/simple

# Setup native dependencies
cd $BUILD_DIR 

git submodule update --init --recursive
pip install pixman
pip install /SharedWorkSpace/devtools/libxext-1.3.6-py3-none-any.whl

# PIXMAN setup
export PIXMAN_INCLUDE=$(python -c "import pixman, os; print(os.path.join(os.path.dirname(pixman.__file__), 'lib', 'include'))")
export PIXMAN_LIB=$(python -c "import pixman, os; print(os.path.join(os.path.dirname(pixman.__file__), 'lib', 'lib'))")

# Append PIXMAN paths
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$PIXMAN_LIB/pkgconfig"
export CFLAGS="${CFLAGS:+$CFLAGS }-I$PIXMAN_INCLUDE"
export CFLAGS="${CFLAGS:+$CFLAGS } -I/usr/include/"
export LDFLAGS="${LDFLAGS:+$LDFLAGS } -L$PIXMAN_LIB"

# LIBXEXT setup
export LIBXEXT_INCLUDE=$(python -c "import libxext, os; print(os.path.join(os.path.dirname(libxext.__file__), 'lib', 'include'))")
export LIBXEXT_LIB=$(python -c "import libxext, os; print(os.path.join(os.path.dirname(libxext.__file__), 'lib', 'lib'))")

# Append LIBXEXT paths
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$LIBXEXT_LIB/pkgconfig"
export CFLAGS="${CFLAGS:+$CFLAGS }-I$LIBXEXT_INCLUDE"
export CFLAGS="${CFLAGS:+$CFLAGS } -I/usr/include/ -DPACKAGE=\"cairo\" -DPACKAGE_VERSION=\"$PKG_VERSION\" -DCAIRO_NO_MUTEX=1"
export LDFLAGS="${LDFLAGS:+$LDFLAGS } -L$LIBXEXT_LIB -L/usr/lib64 -L/usr/lib"
export LIBS="${LIBS:+$LIBS } -lbfd -liberty"

# Synchronize compiler flags
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }$CFLAGS"
export CPPFLAGS="${CPPFLAGS:+$CPPFLAGS }$CFLAGS"

# Build the native C++ code
mkdir -p "$INSTALL_DIR"
./autogen.sh
./configure --prefix=$INSTALL_DIR
make -j$(nproc)
make install

# Build the wheel
cd $PKG_DIR
python -m build
WHEEL_FILE=$(ls dist/"${PKG_NAME}"-"${PKG_VERSION}"-*.whl | head -n 1)

# Install
if ! (pip install "$WHEEL_FILE" --extra-index-url https://pypi.org/simple) ; then
    echo "------------------$PACKAGE_NAME:Install_fails-------------------------------------"
    echo "$PACKAGE_URL $PACKAGE_NAME"
    echo "$PACKAGE_NAME  |  $PACKAGE_URL | $PACKAGE_VERSION | GitHub | Fail |  Install_Fails"
    exit 1
fi

echo "------------------$PACKAGE_NAME:Install_success-------------------------"

# Setup runtime environment variables
cd $ROOT_DIR 
PKG_UPPER=$(echo "$PKG_NAME" | tr '[:lower:]' '[:upper:]')
BASE_PATH=$(python -c "import ${PKG_NAME}, os; print(os.path.join(os.path.dirname(${PKG_NAME}.__file__), 'wheel_payload'))")

# Set library paths
LIB_PATHS=()
if [ -d "$BASE_PATH/lib" ]; then
  LIB_PATHS+=("$BASE_PATH/lib")
fi
if [ -d "$BASE_PATH/lib64" ]; then
  LIB_PATHS+=("$BASE_PATH/lib64")
fi

# Set include paths
if [ -d "$BASE_PATH/include" ]; then
  export CFLAGS="${CFLAGS:+$CFLAGS }-I$BASE_PATH/include"
  export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-I$BASE_PATH/include"
  export CPPFLAGS="${CPPFLAGS:+$CPPFLAGS }-I$BASE_PATH/include"
fi

# Add lib paths to linker and pkg-config
for lib_dir in "${LIB_PATHS[@]}"; do
  export LDFLAGS="${LDFLAGS:+$LDFLAGS }-L$lib_dir"
  export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$lib_dir/pkgconfig"
done

# Add binaries to PATH
if [ -d "$BASE_PATH/bin" ]; then
  export PATH="$BASE_PATH/bin:$PATH"
fi

# Test
cd $BUILD_DIR
if ! (make check); then
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
