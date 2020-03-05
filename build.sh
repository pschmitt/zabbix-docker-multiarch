#!/usr/bin/env bash

usage() {
  echo "$(basename "$0") TARGET [GITREF] [--push]"
}

get_latest_tag() {
  git tag -l | sort -n | tail -1
}

is_latest_tag() {
  [[ "$(get_latest_tag)" == "$1" ]]
}

install_latest_buildx() {
  local arch
  local version=0.3.1
  local buildx_path=~/.docker/cli-plugins/docker-buildx

  if [[ -x "$buildx_path" ]]
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
  mkdir -p "$(dirname "$buildx_path")"
  curl -L -o "$buildx_path" \
    "https://github.com/docker/buildx/releases/download/v${version}/buildx-v${version}.linux-${arch}"
  chmod +x "$buildx_path"
}

setup_buildx() {
  # GitHub Actions
  if [[ -n "$GITHUB_RUN_ID" ]]
  then
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    docker buildx create --use --name builder --node builder --driver docker-container
    docker buildx inspect --bootstrap
    docker buildx inspect
  elif [[ "$TRAVIS" == "true" ]]
  then
    docker buildx create --use --name builder --node builder --driver-opt network=host
  else
    # Not GitHub Actions
    case "$(uname -m)" in
      x86_64|i386)
          echo "Setting up ARM compatibility"
          docker run --rm --privileged docker/binfmt:a7996909642ee92942dcd6cff44b9b95f08dad64
        ;;
    esac
  fi
  # Debug info for buildx and multiarch support
  docker version
  docker buildx ls
  docker buildx inspect --bootstrap
  ls -1 /proc/sys/fs/binfmt_misc
}

get_available_architectures() {
  local image="$1"
  local tag="${2:-latest}"
  local token
  local tmp

  if ! grep -q / <<< "$image"
  then
    # Prepend default namespace
    image="library/${image}"
  fi

  # Disable -x so that the token does not get displayed in the log
  if [[ "$TRAVIS" == "true" ]] || [[ -z "$GITHUB_RUN_ID" ]]
  then
    set +x
  fi

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

  # Re-enable -x for debugging purposes
  if [[ "$TRAVIS" == "true" ]] || [[ -z "$GITHUB_RUN_ID" ]]
  then
    set -x
  fi

  jq -r '.results[] | select(.name == "'"${tag}"'").images[] |
         .os + "/" + .architecture + "/" + .variant' <<< "$tmp" | \
    sed 's#/$##' | sort   # TODO Invalidate token
}

get_available_architectures_safe() {
  # FIXME Statically disabling archs should not be necessary...
  local all_archs

  all_archs=$(get_available_architectures "$@")
  if  [[ "$OS" == "centos" ]]
  then
    grep -vE 'ppc64le|s390x|arm/v6|arm/v7' <<< "$all_archs"
  elif  [[ "$PROJECT" == "agent2" ]]
  then
    grep -vE 'ppc64le|s390x|arm/v6|arm/v7' <<< "$all_archs"
  else
    grep -vE 'ppc64le|s390x' <<< "$all_archs"
  fi
}

array_join() {
  local IFS="$1"
  shift
  echo "$*"
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -x

  cd "$(readlink -f "$(dirname "$0")")" || exit 9

  # buildx setup
  export DOCKER_CLI_EXPERIMENTAL=enabled
  export PATH="$PATH:~/.docker/cli-plugins"
  if ! [[ -x ~/.docker/cli-plugins/docker-buildx ]]
  then
    install_latest_buildx
    setup_buildx
  fi
  if ! docker buildx version >/dev/null
  then
    echo "buildx is not available" >&2
    exit 99
  fi

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

  cd "$BUILD_DIR" || exit 9

  if [[ -z "$GITREF" ]]
  then
    GITREF="$(get_latest_tag)"
  fi

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

  read -r FROM_IMAGE FROM_TAG <<< \
    "$(sed -nr 's/^FROM\s+([^:]+):?((\w+).*)\s*$/\1 \3/p' Dockerfile | head -1)"

  echo "Upstream base image: $FROM_IMAGE TAG=$FROM_TAG"

  TARGET_PLATFORMS=()
  for arch in $(get_available_architectures_safe "$FROM_IMAGE" "$FROM_TAG")
  do
    TARGET_PLATFORMS+=("$arch")
  done

  # Set build labels
  BUILD_LABELS=("--label=built-by=pschmitt")
  if [[ "$TRAVIS" == "true" ]]
  then
    BUILD_LABELS+=("--label=build-type=travis")
  elif [[ -n "$GITHUB_RUN_ID" ]]
  then
    BUILD_LABELS+=("--label=build-type=github-actions" "--label=github-run-id=$GITHUB_RUN_ID")
  else
    BUILD_LABELS+=("--label=build-type=manual" "--label=build-host=$HOSTNAME")
  fi

  if [[ -n "$DRYRUN" ]]
  then
    # shellcheck disable=2046,2068
    echo docker buildx build \
      --platform "$(array_join "," "${TARGET_PLATFORMS[@]}")" \
      --output "type=image,push=${PUSH_IMAGE}" \
      $(array_join " " "${BUILD_LABELS[@]}") \
      ${TAG_ARGS[@]} .
  else
    # shellcheck disable=2046,2068
    docker buildx build \
      --platform "$(array_join "," "${TARGET_PLATFORMS[@]}")" \
      --output "type=image,push=${PUSH_IMAGE}" \
      $(array_join " " "${BUILD_LABELS[@]}") \
      ${TAG_ARGS[@]} .
  fi

  # TODO Detect which architectures failed and retry build without them
fi

# vim set et ts=2 sw=2 :
