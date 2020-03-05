#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") [MAX_TAGS]"
}

list_targets() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  git clone -q --depth 1 https://github.com/zabbix/zabbix-docker "$tmpdir"
  find "$tmpdir" -maxdepth 2 -mindepth 2 -type d | grep -v .git | \
    sed -e "s|^${tmpdir}/||" -e 's|/|-|' | sort
  trap "rm -rf \"$tmpdir\"" EXIT
}

list_remote_tags() {
  git ls-remote --tags "$1" | \
    awk '{print $2}' | \
    sed 's|refs/tags/||' | \
    sort -r
}

travis_build() {
  local target
  local git_tags
  local git_tag
  local jobs_def=""
  local tmp
  local tags_limit="${1:-1}"

  git_tags=$(list_remote_tags https://github.com/zabbix/zabbix-docker)

  # Limit to latest X tags
  git_tags=$(head -n "$tags_limit" <<< "$git_tags")

  for target in $(list_targets)
  do
    for git_tag in $git_tags
    do
      tmp='"TARGET='"$target"' GIT_TAG='"$git_tag"'"'
      if [[ -n "$jobs_def" ]]
      then
        jobs_def="$jobs_def, $tmp"
      else
        jobs_def="$tmp"
      fi
    done
  done

  local body
  body='{
   "request": {
   "message": "'"$(git show -s --format=%s)"' (Auto build)",
   "branch": "'"$(git rev-parse --abbrev-ref HEAD)"'",
   "config": {
     "env": {
       "jobs": ['"$jobs_def"']
     }
    }
  }}'

  curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Travis-API-Version: 3" \
    -H "Authorization: token $TRAVIS_TOKEN" \
    -d "$body" \
    https://api.travis-ci.com/repo/pschmitt%2Fzabbix-docker-armhf/requests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  if [[ -z "$TRAVIS_TOKEN" ]]
  then
    echo "TRAVIS_TOKEN is not set." >&2
    echo "You can retrieve it with $ travis token --com" >&2
    exit 2
  fi

  case "$1" in
    help|h|-h|--help)
      usage
      exit 0
      ;;
  esac

  travis_build "$@"
fi
