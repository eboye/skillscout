#!/usr/bin/env bash
# Builds Skillscout and packs it for Linux, into build/packages:
#
#   Linux/packaging/package.sh deb rpm tarball appimage
#
#   deb       skillscout_<version>-<release>_<arch>.deb, with nfpm
#   rpm       skillscout-<version>-<release>.<arch>.rpm, with nfpm
#   tarball   skillscout-<version>-linux-<arch>.tar.gz, to unpack into ~/.local or /usr/local
#   appimage  Skillscout-<version>-<arch>.AppImage, with GTK and libadwaita inside, via linuxdeploy
#
# The version is upstream's, MARKETING_VERSION in project.yml, so Linux packages follow the Mac
# releases. RELEASE (default 1) counts Linux builds of one version. nfpm, linuxdeploy and its GTK
# plugin get downloaded into build/tools the first time.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
[ $# -gt 0 ] || { echo "usage: $0 deb|rpm|tarball|appimage…" >&2; exit 2; }

export VERSION="${VERSION:-$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)}"
export RELEASE="${RELEASE:-1}"
machine="$(uname -m)"
packages="$root/build/packages"
tools="$root/build/tools"
mkdir -p "$packages" "$tools"

swift build -c release
rm -rf build/stage
STRIP=1 SKIP_BUILD=1 PREFIX=/usr DESTDIR="$root/build/stage" Linux/scripts/install.sh >/dev/null

nfpm() {
  if [ ! -x "$tools/nfpm" ]; then
    local arch=x86_64
    [ "$machine" = aarch64 ] && arch=arm64
    curl -sSfL "https://github.com/goreleaser/nfpm/releases/download/v2.47.0/nfpm_2.47.0_Linux_$arch.tar.gz" | tar -xz -C "$tools" nfpm
  fi
  "$tools/nfpm" "$@"
}

for format in "$@"; do
  case "$format" in
    deb)
      debarch=amd64
      [ "$machine" = aarch64 ] && debarch=arm64
      ARCH="$debarch" nfpm package --config Linux/packaging/nfpm.yaml --packager deb --target "$packages/skillscout_${VERSION}-${RELEASE}_$debarch.deb"
      ;;
    rpm)
      ARCH="$machine" nfpm package --config Linux/packaging/nfpm.yaml --packager rpm --target "$packages/skillscout-${VERSION}-${RELEASE}.$machine.rpm"
      ;;
    tarball)
      name="skillscout-$VERSION-linux-$machine"
      rm -rf "build/$name"
      cp -a build/stage/usr "build/$name"
      cp LICENSE "build/$name/"
      tar -C build -czf "$packages/$name.tar.gz" "$name"
      rm -rf "build/$name"
      ;;
    appimage)
      Linux/packaging/appimage.sh "$packages/Skillscout-$VERSION-$machine.AppImage"
      ;;
    *)
      echo "Unknown format: $format" >&2
      exit 2
      ;;
  esac
done
ls -la "$packages"
