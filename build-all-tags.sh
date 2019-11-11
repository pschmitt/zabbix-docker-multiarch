#!/usr/bin/env bash

cd "$(readlink -f "$(dirname "$0")")" || exit 9

usage() {
  echo "Usage: $(basename "$0") TARGET"
}

list_remote_tags() {
  git ls-remote --tags "$1" | \
    awk '{print $2}' | \
    sed 's|refs/tags/||'
}

if [[ "$#" -lt 1 ]]
then
  usage
  exit 2
fi

case "$1" in
  -h|--help|help|h)
    usage
    exit 0
    ;;
esac

for git_tag in $(list_remote_tags https://github.com/zabbix/zabbix-docker)
do
  ./build.sh "$1" "$git_tag" -p
done
