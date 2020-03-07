# Zabbix Multiarch Docker images

[![Build Status](https://travis-ci.com/pschmitt/zabbix-docker-multiarch.svg?branch=master)](https://travis-ci.com/pschmitt/zabbix-docker-multiarch)

You can find the resulting images in the [zabbixmultiarch Docker Hub organization](https://hub.docker.com/u/zabbixmultiarch).

## Setup

To get started please refer to the [upstream documentation](https://www.zabbix.com/container_images).

Since this here project builds the exact same images as upstream you can simply replace the image names.

The only thing you need to worry about are the tag/image names, intead of `zabbix/zabbix-agent:alpine-latest` you need to use `zabbixmultiarch/zabbix-agent-alpine:latest`.

I might change this in the future so that it is even more transparent.

### Example

#### Proxy

```bash
docker run --name some-zabbix-proxy-sqlite3 -e ZBX_HOSTNAME=some-hostname -e ZBX_SERVER_HOST=some-zabbix-server -d zabbixmultiarch/zabbix-proxy-sqlite3-alpine:tag
```

#### Agent

```bash
docker run --name some-zabbix-agent -e ZBX_HOSTNAME="some-hostname" -e ZBX_SERVER_HOST="some-zabbix-server" -d zabbixmultiarch/zabbix-agent-alpine:tag
```
