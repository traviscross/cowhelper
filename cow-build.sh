#!/bin/bash
set -e

usage () {
  echo "$0 [-u <upstream-branch>] [-a <archs>] [-c <distros>]">&2
}

suite_from () {
  case "$1" in
    sid) echo "unstable";;
    jessie) echo "testing";;
    wheezy) echo "stable";;
    squeeze) echo "oldstable";;
    *) echo "$1";;
  esac
}

source () {
  dpkg-parsechangelog \
    | grep -m1 '^Source:' \
    | awk '{print $2}'
}

version () {
  dpkg-parsechangelog \
    | grep -m1 '^Version:' \
    | awk '{print $2}' \
    | sed -e 's/^[0-9]\+://'
}

upstream_version () {
  version | sed -e 's/-.*//'
}

native_p () {
  version | grep '-' >/dev/null || return 0
  return 1
}

maintainer () {
  cat debian/control \
    | grep -m1 ^Maintainer: \
    | sed 's/.*: //'
}

author () {
  dpkg-parsechangelog \
    | grep -m1 ^Maintainer: \
    | sed 's/.*: //'
}

nmu_p () {
  test "$(author)" != "$(maintainer)"
}

make_archive () {
  if test -x debian/archive; then
    ./debian/archive "$upstream"
  elif test -x debian/archive.sh; then
    ./debian/archive.sh "$upstream"
  elif test -x "$(which git-dpkg-mkarchive)"; then
    git-dpkg-mkarchive "$upstream"
  else
    git archive --prefix="$(source)/" "$upstream" \
      | xz -c9v > "../$(source)_$(upstream_version).orig.tar.xz"
  fi
}

make_patches () {
  if test -x "$(which git-dpkg-mkquilt)"; then
    git-dpkg-mkquilt "$upstream"
  fi
}

cow_build () {
  local src="$(source)"
  local ver="$(version)"
  local dsc="../${src}_${ver}.dsc"
  local src_changes="../${src}_${ver}_source.changes"
  rm -f "../$(source)*.{changes,deb,dsc}"
  git clean -fdx && git reset --hard HEAD
  if test -n "$upstream"; then
    make_archive
    make_patches
  fi
  for distro in $distros; do
    local suite="$(suite_from $distro)" indep_build=true
    if test ! "$distro" = "sid"; then
      dsc="../${src}_${ver}~${distro}.dsc"
      src_changes="../${src}_${ver}~${distro}_source.changes"
      dch -b -m -v "$ver~$distro" \
        --force-distribution -D "$suite" \
        "NMU: Port to ${distro}."
    fi
    dpkg-source -i.* -Zxz -z9 -b .
    dpkg-genchanges -S -sa > "$src_changes"
    git clean -fdx && git reset --hard HEAD
    for arch in $archs; do
      local cow_img="/var/cache/pbuilder/base-$distro-$arch.cow"
      cow () {
        cowbuilder "$@" \
          --distribution "$distro" \
          --architecture "$arch" \
          --basepath "$cow_img"
      }
      test ! -d "$cow_img" && cow-update -a "$arch" -c "$distro"
      local opts="-B"
      $indep_build && opts="-b"
      cow --build "$dsc" \
        --buildresult "../" \
        --debbuildopts "$opts"
      indep_build=false
    done
  done
}

upstream=""
archs="amd64"
distros="sid"
test -z "$COWHELPER_ARCHS" || archs="$COWHELPER_ARCHS"
test -z "$COWHELPER_DISTROS" || distros="$COWHELPER_DISTROS"
while getopts "a:c:hu:" o; do
  case "$o" in
    h) usage; exit 0 ;;
    u) upstream="$OPTARG" ;;
    a) archs="$OPTARG" ;;
    c) distros="$OPTARG" ;;
  esac
done
shift $(($OPTIND-1))

if test -z "$upstream" && ! native_p; then
  printf "Error: must specify upstream for non-native package\n\n">&2
  usage
  exit 1
fi

if test $(git diff-index HEAD | wc -l) -gt 0; then
  printf 'Error: dirty tree; stash or commit your changes first\n'>&2; exit 1; fi
if test $(git diff-index --cached HEAD | wc -l) -gt 0; then
  printf 'Error: dirty index; stash or commit your changes first\n'>&2; exit 1; fi
if test $(git ls-files --others | wc -l) -gt 0; then
  printf 'Error: untracked files; stash or commit your changes first\n'>&2; exit 1; fi

cow_build
