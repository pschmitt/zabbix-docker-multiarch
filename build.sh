#!/usr/bin/env bash

usage() {
  echo "$(basename "$0") TARGET [GITREF] [--push]"
}

is_latest_tag() {
  [[ "$(git tag -l | sort -n | tail -1)" == "$1" ]]
}

install_latest_buildx() {
  local arch
  local version=0.3.1

  if [[ -x ~/.docker/cli-plugins/docker-buildx ]]
  then
    return
  fi

  case "$(uname -m)" in
    x86_64)
      arch=amd64
      ;;
    aarch64)
      arch=arm64
      ;;
    armv6l|arm)
      arch=arm-v6
      ;;
    armv7l|armhf)
      arch=arm-v7
      ;;
    *)
      arch="$(uname -m)"
      ;;
  esac
  mkdir -p ~/.docker/cli-plugins
  curl -L -o ~/.docker/cli-plugins/docker-buildx \
    "https://github.com/docker/buildx/releases/download/v${version}/buildx-v${version}.linux-${arch}"
  chmod +x ~/.docker/cli-plugins/docker-buildx

  # if [[ "$TRAVIS" == "true" ]]
  # then
  #   echo '{"experimental": "enabled"}' > ~/.docker/config.json
  #   sudo service docker restart
  # fi
}

get_available_architectures() {
  local token image="$1" tag="${2:-latest}"
  local tmp

  token=$(curl -s -H "Content-Type: application/json" \
            -X POST \
            -d '{"username": "'"${DOCKER_USERNAME}"'", "password": "'"${DOCKER_PASSWORD}"'"}' \
            https://hub.docker.com/v2/users/login/ | \
           jq -r .token)
  if [[ -z "$token" ]]
  then
    echo "Unable to log in to Docker Hub." >&2
    echo "Please verify the values of DOCKER_USERNAME and DOCKER_PASSWORD" >&2
    return 1
  fi
  tmp="$(curl -s -H "Authorization: JWT ${token}" \
          "https://hub.docker.com/v2/repositories/${image}/tags/?page_size=10000")"
  jq -r '.results[] | select(.name == "'"${tag}"'").images[] |
         .os + "/" + .architecture + "/" + .variant' <<< "$tmp" | \
    sed 's#/$##' | sort
}

array_join() {
  local IFS="$1"
  shift
  echo "$*"
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -ex

  cd "$(readlink -f "$(dirname "$0")")" || exit 9

  if [[ "$#" -lt 1 ]]
  then
    usage
    exit 2
  fi

  case "$1" in
    -h|--help|h|help)
      usage
      exit 0
      ;;
  esac

  TARGET="$1"
  # Defaults
  GITREF=master
  PUSH_IMAGE=false

  case "$2" in
    -f|--force|-p|--push)
      PUSH_IMAGE=true
      ;;
    *)
      GITREF="$2"
      case "$3" in
        -f|--force|-p|--push)
          PUSH_IMAGE=true
          ;;
      esac
      ;;
  esac

  read -r PROJECT OS <<< "$(sed -r 's/(.+)-(.+)/\1 \2/' <<< "$TARGET")"

  if [[ -z "$PROJECT" ]] || [[ -z "$OS" ]]
  then
    echo "Unable to determine target project or OS" >&2
    exit 3
  fi

  BUILD_DIR="${PWD}/data"

  if [[ -d "$BUILD_DIR" ]]
  then
    cd "$BUILD_DIR" || exit 9
    git clean -d -f -f
    git reset --hard HEAD > /dev/null
    git checkout master
    git pull > /dev/null
  else
    git clone https://github.com/zabbix/zabbix-docker "$BUILD_DIR"
  fi

  cd "$BUILD_DIR"

  git checkout "$GITREF"

  if ! cd "${BUILD_DIR}/${PROJECT}/${OS}" 2> /dev/null
  then
    echo "No such project/OS combination: ${PROJECT} on ${OS}" >&2
    exit 4
  fi

  if [[ "$GITREF" == "master" ]]
  then
    DOCKER_TAG=latest
  else
    DOCKER_TAG="$GITREF"
  fi

  DOCKER_IMAGES=("pschmitt/zabbix-${PROJECT}-${OS}:${DOCKER_TAG}")
  if is_latest_tag "$GITREF"
  then
    DOCKER_IMAGES+=("pschmitt/zabbix-${PROJECT}-${OS}:latest")
  fi
  echo "Building ${DOCKER_IMAGES[0]}"

  TAG_ARGS=()
  for img in "${DOCKER_IMAGES[@]}"
  do
    TAG_ARGS+=("--tag $img")
  done

  case "$(uname -m)" in
    x86_64|i386)
      echo "Setting up ARM compatibility"
      # docker run --rm --privileged docker/binfmt:820fdd95a9972a5308930a2bdfb8573dd4447ad3
      docker run --rm --privileged docker/binfmt:a7996909642ee92942dcd6cff44b9b95f08dad64
      ;;
  esac

  # buildx setup
  export DOCKER_CLI_EXPERIMENTAL=enabled
  install_latest_buildx
  if ! docker buildx version
  then
    echo "buildx is not available" >&2
    exit 99
  fi

  if [[ "$TRAVIS" == "true" ]]
  then
    docker buildx create --use --name build --node build --driver-opt network=host
  fi

  read -r FROM_IMAGE FROM_TAG <<< \
    "$(sed -nr 's/FROM\s+([^:]+):?([^\s]*)?(as .*)?/\1 \2/p' Dockerfile | head -1)"
  if ! grep -q / <<< "$FROM_IMAGE"
  then
    # Prepend default namespace
    FROM_IMAGE="library/${FROM_IMAGE}"
  fi

  echo "Upstream base image: $FROM_IMAGE TAG=$FROM_TAG"

  TARGET_PLATFORMS=()
  for arch in $(get_available_architectures "$FROM_IMAGE" "$FROM_TAG")
  do
    TARGET_PLATFORMS+=("$arch")
  done

  # shellcheck disable=2068
  docker buildx build \
    --platform "$(array_join "," "${TARGET_PLATFORMS[@]}")" \
    --output "type=image,push=${PUSH_IMAGE}" \
    ${TAG_ARGS[@]} .
fi

# vim set et ts=2 sw=2 :
