#!/usr/bin/env bash

list_targets() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  git clone -q --depth 1 https://github.com/zabbix/zabbix-docker "$tmpdir"
  find "$tmpdir" -maxdepth 2 -mindepth 2 -type d | grep -v .git | \
    sed -e "s|^${tmpdir}/||" -e 's|/|-|'
  trap "rm -rf \"$tmpdir\"" EXIT
}

for target in $(list_targets)
do
  echo "# BUILD $target"
  ./build-all-tags.sh "$target"
done
