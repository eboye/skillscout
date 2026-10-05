#!/usr/bin/env bash
# Installs a Swift toolchain from swift.org into /opt/swift, for the package builds.
#
#   Linux/packaging/install-swift.sh ubuntu26.04|ubuntu24.04|fedora41 [version]
#
# On a distribution swift.org doesn't build for, like Arch, pick the closest one: the script links
# the libraries that distribution names differently. With GITHUB_PATH set, it adds Swift to the PATH
# of the next steps; otherwise it prints the folder to add.
set -euo pipefail

platform="${1:?which toolchain: ubuntu26.04, ubuntu24.04 or fedora41}"
version="${2:-6.4.0}"
folder="swift-$version-RELEASE-$platform"
url="https://download.swift.org/swift-$version-release/${platform//./}/swift-$version-RELEASE/$folder.tar.gz"
prefix="${SWIFT_PREFIX:-/opt/swift}"

mkdir -p "$prefix"
curl -sSfL "$url" | tar -xz -C "$prefix"
bin="$prefix/$folder/usr/bin"
lib="$prefix/$folder/usr/lib/swift/linux"

# The toolchain wants these sonames. Where a distribution only has another name for the same
# library, a link in the toolchain's own folder covers it.
# Read once: grep -q and awk's exit close the pipe early, which fails ldconfig under pipefail.
libraries="$(ldconfig -p)"
path_of() { awk -v name="$1" '$1 == name { print $NF }' <<< "$libraries" | head -1; }
link() {
  local wanted="$1" source
  [ -n "$(path_of "$wanted")" ] && return
  shift
  for source in "$@"; do
    if [ -n "$(path_of "$source")" ]; then
      ln -sf "$(path_of "$source")" "$lib/$wanted"
      return
    fi
  done
}
link libncurses.so.6 libncursesw.so.6
link libtinfo.so.6 libncursesw.so.6 libtinfow.so.6
link libpanel.so.6 libpanelw.so.6
link libform.so.6 libformw.so.6
link libxml2.so.2 libxml2.so.16
link libedit.so.2 libedit.so.0

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bin" >> "$GITHUB_PATH"
fi
"$bin/swift" --version >&2
echo "$bin"
