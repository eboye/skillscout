#!/usr/bin/env bash
# Prints the version Linux packages get, which is upstream's MARKETING_VERSION in project.yml, and
# fails when a Linux file that repeats it has fallen behind: the PKGBUILD, the AppStream release
# and the About dialog. With a tag as the argument, it also checks the tag is v<version>, or
# v<version>-linux.<n> for a Linux rebuild of the same version, and prints that n as the release.
#
#   Linux/packaging/version.sh            1.4.0 1
#   Linux/packaging/version.sh v1.4.0     1.4.0 1
#   Linux/packaging/version.sh v1.4.0-linux.2   1.4.0 2
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)"
status=0

check() {
  local file="$1" found="$2"
  if [ "$found" != "$version" ]; then
    echo "$file has version '$found', but project.yml has $version" >&2
    status=1
  fi
}
check Linux/arch/PKGBUILD "$(sed -n 's/^pkgver=//p' Linux/arch/PKGBUILD)"
check Linux/com.flaviocopes.skillscout.metainfo.xml "$(grep -o '<release version="[^"]*"' Linux/com.flaviocopes.skillscout.metainfo.xml | head -1 | cut -d'"' -f2)"
check Linux/App/Dialogs.swift "$(sed -n 's/^let appVersion = "\(.*\)"/\1/p' Linux/App/Dialogs.swift)"

release=1
if [ $# -gt 0 ]; then
  tag="$1"
  case "$tag" in
    "v$version") ;;
    "v$version"-linux.*) release="${tag#"v$version"-linux.}" ;;
    *) echo "Tag $tag doesn't match version $version: use v$version or v$version-linux.<n>" >&2; status=1 ;;
  esac
fi

[ "$status" = 0 ] || exit 1
echo "$version $release"
