# Zabbix Multiarch Docker images

[![Build Status](https://travis-ci.com/pschmitt/zabbix-docker-multiarch.svg?branch=master)](https://travis-ci.com/pschmitt/zabbix-docker-multiarch)

![GitHub Actions CI](https://github.com/pschmitt/zabbix-docker-multiarch/workflows/GitHub%20Actions%20CI/badge.svg)

You can find the resulting images in the [zabbixmultiarch Docker Hub organization](https://hub.docker.com/u/zabbixmultiarch).

## Setup

To get started please refer to the [upstream documentation](https://www.zabbix.com/container_images).

Since this here project builds the exact same images as upstream you can simply replace the image names.

- `zabbix/zabbix-agent` becomes `zabbixmultiarch/zabbix-agent`
- `zabbix/zabbix-server-mysql` becomes `zabbixmultiarch/zabbix-server-mysql`
- `zabbix/zabbix-proxy-sqlite3` becomes `zabbixmultiarch/zabbix-proxy-sqlite3`
- etc.

### Examples

#### Proxy

```bash
docker run --name some-zabbix-proxy-sqlite3 -e ZBX_HOSTNAME=some-hostname -e ZBX_SERVER_HOST=some-zabbix-server -d zabbixmultiarch/zabbix-proxy-sqlite3:tag
```

#### Agent

```bash
docker run --name some-zabbix-agent -e ZBX_HOSTNAME="some-hostname" -e ZBX_SERVER_HOST="some-zabbix-server" -d zabbixmultiarch/zabbix-agent:tag
```

## CI

All upstream projects are built using both [Travis CI](https://travis-ci.com/pschmitt/zabbix-docker-multiarch) and [GitHub Actions](https://github.com/pschmitt/zabbix-docker-multiarch/actions?query=workflow%3A%22GitHub+Actions+CI%22)
**except** zabbix-agent2 since [it won't build properly with buildx and QEMU for ARM](https://github.com/pschmitt/zabbix-docker-multiarch/issues/3).

I currently build zabbix-agent2 locally every day using an AMD64 machine and a Raspberry Pi.

Sadly due to https://github.com/docker/buildx/issues/177 only the `latest` tag get published for the moment.
