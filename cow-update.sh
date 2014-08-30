#!/bin/bash
set -e

get_sources () {
  local tgt_suite="$1"
  while read type path suite components; do
    test "$type" = deb || continue
    printf "$type $path $tgt_suite $components\n"
  done < /etc/apt/sources.list
}

get_mirrors () {
  get_sources "$1" | tr '\n' '|' | head -c-1; echo
}

cow_update () {
  local suites="$1" archs="$2"
  local keyring="$(mktemp /tmp/keyringXXXXXXXX.asc)"
  apt-key exportall > $keyring
  for suite in $suites; do
    for arch in $archs; do
      printf "### Updating $suite/$arch\n\n">&2
      local cow_img="/var/cache/pbuilder/base-$suite-$arch.cow"
      cow () {
        printf "### Running cowbuilder $@ ($suite/$arch)...\n">&2
        cowbuilder "$@" \
          --distribution "$suite" \
          --architecture "$arch" \
          --basepath "$cow_img" \
          --override-config \
          --keyring "$keyring" \
          --othermirror "$(get_mirrors $suite)"
      }
      test -d "$cow_img" || cow --create
      cow --update
    done
  done
  rm -f "$keyring"
}

usage () {
  echo "$0 [-a <archs>] [-c <suites>]">&2
}

archs="amd64"
suites="sid"
test -z "$COWHELPER_ARCHS" || archs="$COWHELPER_ARCHS"
test -z "$COWHELPER_SUITES" || suites="$COWHELPER_SUITES"
while getopts "a:c:h" o; do
  case "$o" in
    h) usage; exit 0 ;;
    a) archs="$OPTARG" ;;
    c) suites="$OPTARG" ;;
  esac
done
shift $(($OPTIND-1))

cow_update "$suites" "$archs"
