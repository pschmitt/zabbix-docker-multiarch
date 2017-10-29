#!/usr/bin/env bash

set -e

cd "$(readlink -f "$(dirname "$0")")" || exit 9

usage() {
    echo "$(basename $0) TARGET"
}

if [[ -z "$1" ]]
then
    usage
    exit 2
fi

read -r PROJECT OS <<< "$(sed -r 's/(.+)-(.+)/\1 \2/' <<< "$1")"

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
    git pull > /dev/null
else
    git clone https://github.com/zabbix/zabbix-docker "$BUILD_DIR"
fi

if ! cd "${BUILD_DIR}/${PROJECT}/${OS}" 2> /dev/null
then
    echo "No such project/OS combination: ${PROJECT} on ${OS}" >&2
    exit 4
fi

read -r ORIG_BASE_DOCKER_IMAGE DOCKER_TAG <<< "$(sed -nr 's/FROM (.+):(.+)/\1 \2/p' Dockerfile)"

case "$ORIG_BASE_DOCKER_IMAGE" in
    alpine)
        BASE_DOCKER_IMAGE='resin\/raspberry-pi-alpine'
        ;;
    ubuntu)
        BASE_DOCKER_IMAGE='arm32v7\/ubuntu'
        # BASE_DOCKER_IMAGE='resin\/rpi-raspbian'
        ;;
    *)
        echo "Unable to find a suitable replacement for $BASE_DOCKER_IMAGE" >&2
        exit 5
        ;;
esac

# Use eval to interpret the '\/' char
echo "Rebasing on $(eval echo $BASE_DOCKER_IMAGE)"
sed -i 's/FROM .*/FROM '"${BASE_DOCKER_IMAGE}"':'"${DOCKER_TAG}"'/' Dockerfile

DOCKER_IMAGE="pschmitt/zabbix-${PROJECT}-${OS}-armhf"
echo "Building $DOCKER_IMAGE"

case $(uname -m) in
    x86_64|i386)
        echo "Setting up ARM compatibility"
        docker run --rm --privileged multiarch/qemu-user-static:register --reset > /dev/null
        ;;
esac

docker build -t "$DOCKER_IMAGE" .

# docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"

case "$2" in
    -f|--force|-p|--push)
        docker push "$DOCKER_IMAGE"
        ;;
esac
