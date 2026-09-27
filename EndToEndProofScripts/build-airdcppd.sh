#!/bin/sh
# Builds airdcppd 2.14.0 natively (dynamically linked; proof only).
set -e
S=/private/tmp/claude-502/-Users-jacobcarlborg-development-doobnet-airdc-mac/e80c385b-2c43-46d4-aad6-a078a7136e25/scratchpad
cd "$S/airdcpp-webclient"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DINSTALL_WEB_UI=OFF \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3 \
  "-DCMAKE_PREFIX_PATH=$S/prefix;/opt/homebrew" \
  "-DCMAKE_INSTALL_PREFIX=$S/prefix"
cmake --build build
