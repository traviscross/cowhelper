#!/bin/bash
set -e

get_sources () {
  local tgt_distro="$1"
  while read type path distro components; do
    test "$type" = deb || continue
    printf "$type $path $tgt_distro $components\n"
  done < /etc/apt/sources.list
}

get_mirrors () {
  get_sources "$1" | tr '\n' '|' | head -c-1; echo
}

cow_update () {
  local distros="$1" archs="$2"
  local keyring="$(mktemp /tmp/keyringXXXXXXXX.asc)"
  apt-key exportall > $keyring
  for distro in $distros; do
    for arch in $archs; do
      printf "### Updating $distro/$arch\n\n">&2
      local cow_img="/var/cache/pbuilder/base-$distro-$arch.cow"
      cow () {
        printf "### Running cowbuilder $@ ($distro/$arch)...\n">&2
        cowbuilder "$@" \
          --distribution "$distro" \
          --architecture "$arch" \
          --basepath "$cow_img" \
          --override-config \
          --keyring "$keyring" \
          --othermirror "$(get_mirrors $distro)"
      }
      test -d "$cow_img" || cow --create
      cow --update
    done
  done
  rm -f "$keyring"
}

usage () {
  echo "$0 [-a <archs>] [-c <distros>]">&2
}

archs="amd64"
distros="sid"
test -z "$COWHELPER_ARCHS" || archs="$COWHELPER_ARCHS"
test -z "$COWHELPER_DISTROS" || distros="$COWHELPER_DISTROS"
while getopts "a:c:h" o; do
  case "$o" in
    h) usage; exit 0 ;;
    a) archs="$OPTARG" ;;
    c) distros="$OPTARG" ;;
  esac
done
shift $(($OPTIND-1))

cow_update "$distros" "$archs"
