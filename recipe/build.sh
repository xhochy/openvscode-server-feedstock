#!/bin/bash

set -exuo pipefail

rm $PREFIX/bin/node
ln -s $BUILD_PREFIX/bin/node $PREFIX/bin/node

if [[ "${target_platform}" == "linux-64" ]]; then
  ARCH_ALIAS=linux-x64
elif [[ "${target_platform}" == "linux-aarch64" ]]; then
  ARCH_ALIAS=linux-arm64
  export npm_config_arch="arm64"
elif [[ "${target_platform}" == "osx-64" ]]; then
  ARCH_ALIAS=darwin-x64
elif [[ "${target_platform}" == "osx-arm64" ]]; then
  ARCH_ALIAS=darwin-arm64
  export npm_config_arch="arm64"
fi

pushd src
git init
git config core.precomposeunicode false
git add .
git config --local user.email 'noreply@example.com'
git config --local user.name 'conda smithy'
git commit -m "placeholder commit" --no-verify --no-gpg-sign
# Install remote extensions for target_platform
pushd remote
  VSCODE_RIPGREP_VERSION=$(jq -r '.dependencies."@vscode/ripgrep"' package.json)
  # Install all dependencies except @vscode/ripgrep
  mv package.json package.json.orig
  jq 'del(.dependencies."@vscode/ripgrep")' package.json.orig > package.json
  yarn install
  # Install @vscode/ripgrep without downloading the pre-built ripgrep.
  # This often runs into Github API ratelimits and we won't use the binary in this package anyways.
  yarn add --ignore-scripts "@vscode/ripgrep@${VSCODE_RIPGREP_VERSION}"
popd
# Install build tools for build_platform
(
  unset CFLAGS
  unset CXXFLAGS
  unset CPPFLAGS
  unset npm_config_arch
  export CC=${CC_FOR_BUILD}
  export CXX=${CXX_FOR_BUILD}
  export AR="$($CC_FOR_BUILD -print-prog-name=ar)"
  export NM="$($CC_FOR_BUILD -print-prog-name=nm)"
  export LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
  export PKG_CONFIG_PATH=${BUILD_PREFIX}/lib/pkgconfig
  VSCODE_RIPGREP_VERSION=$(jq -r '.dependencies."@vscode/ripgrep"' package.json)
  # Install all dependencies except @vscode/ripgrep
  mv package.json package.json.orig
  jq 'del(.dependencies."@vscode/ripgrep")' package.json.orig > package.json
  yarn install
  # Install @vscode/ripgrep without downloading the pre-built ripgrep.
  # This often runs into Github API ratelimits and we won't use the binary in this package anyways.
  yarn add --ignore-scripts "@vscode/ripgrep@${VSCODE_RIPGREP_VERSION}"
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
mkdir -p ${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin
cat <<EOF >${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg
#!/bin/bash
exec "${PREFIX}/bin/rg" "\$@"
EOF
chmod +x ${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg

if [[ "${CROSSCOMPILING_EMULATOR:-}" != "" ]]; then
  ${PREFIX}/share/openvscode-server/node_modules/@vscode/ripgrep/bin/rg --help

  # Directly check whether the openvscode-server call also works inside of conda-build
  openvscode-server --help
fi
