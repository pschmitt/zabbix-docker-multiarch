#!/usr/bin/env bash

TARGETS=(
  agent-alpine
  proxy-mysql-alpine
  proxy-sqlite3-alpine
  server-mysql-alpine
  server-pgsql-alpine
  web-apache-mysql-alpine
  web-apache-pgsql-alpine
  web-nginx-mysql-alpine
  web-nginx-pgsql-alpine
)

for target in ${TARGETS[@]}
do
  echo "# BUILD $target"
  ./build-all-tags.sh "$target"
done
