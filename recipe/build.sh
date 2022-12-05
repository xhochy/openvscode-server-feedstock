#!/bin/bash

set -exuo pipefail

rm $PREFIX/bin/node
ln -s $BUILD_PREFIX/bin/node $PREFIX/bin/node

if [[ "${target_platform}" == "linux-64" ]]; then
  ARCH_ALIAS=linux-x64
elif [[ "${target_platform}" == "linux-aarch64" ]]; then
  ARCH_ALIAS=linux-arm64
elif [[ "${target_platform}" == "osx-64" ]]; then
  ARCH_ALIAS=darwin-x64
elif [[ "${target_platform}" == "osx-arm64" ]]; then
  ARCH_ALIAS=darwin-arm64
fi

pushd src
git init
git config core.precomposeunicode false
git add .
git config --local user.email 'noreply@example.com'
git config --local user.name 'conda smithy'
git commit -m "placeholder commit" --no-verify --no-gpg-sign
# Install build tools for build_platform
(
  unset CFLAGS
  unset CXXFLAGS
  unset CPPFLAGS
  export CC=${CC_FOR_BUILD}
  export CXX=${CXX_FOR_BUILD}
  export AR="$($CC_FOR_BUILD -print-prog-name=ar)"
  export NM="$($CC_FOR_BUILD -print-prog-name=nm)"
  export LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
  export PKG_CONFIG_PATH=${BUILD_PREFIX}/lib/pkgconfig
  yarn install
)
yarn gulp vscode-reh-web-${ARCH_ALIAS}-min
popd

mkdir -p $PREFIX/share
cp -r vscode-reh-web-${ARCH_ALIAS} ${PREFIX}/share/openvscode-server
rm -rf $PREFIX/share/openvscode-server/bin

mkdir -p ${PREFIX}/bin

cat <<'EOF' >${PREFIX}/bin/openvscode-server
#!/bin/bash
PREFIX_DIR=$(dirname ${BASH_SOURCE})
# Make PREDIX_DIR absolute
if [[ $(uname) == 'Linux' ]]; then
  PREFIX_DIR=$(readlink -f ${PREFIX_DIR})
else
  pushd ${PREFIX_DIR}
  PREFIX_DIR=$(pwd -P)
  popd
fi
# Go one level up
PREFIX_DIR=$(dirname ${PREFIX_DIR})
node "${PREFIX_DIR}/share/openvscode-server/out/server-main.js" "$@"
EOF
chmod +x ${PREFIX}/bin/openvscode-server

# Remove unnecessary resources
find ${PREFIX}/share/openvscode-server -name '*.map' -delete
rm -rf ${PREFIX}/share/openvscode-server/node

# Replace bundled ripgrep with conda package
rm ${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg
cat <<EOF >${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg
#!/bin/bash
exec "${PREFIX}/bin/rg" "\$@"
EOF
chmod +x ${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg
${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg --help

# Directly check whether the openvscode-server call also works inside of conda-build
openvscode-server --help
