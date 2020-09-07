#!/usr/bin/env bash

set -e

PROTOCOL=${PROTOCOL:-dev}

# Probably should always be 0.0.0.0
HOST=${HOST:-0.0.0.0}
PORT=${PORT:-4334}

## Recommended settings for -Xmx1g usage, e.g. dev laptops.
MEMORY_INDEX_THRESHOLD=${MEMORY_INDEX_THRESHOLD:-32m}
MEMORY_INDEX_MAX=${MEMORY_INDEX_MAX:-256m}
OBJECT_CACHE_MAX=${OBJECT_CACHE_MAX:-128m}

## Recommended settings for -Xmx4g production usage.
#MEMORY_INDEX_THRESHOLD=${MEMORY_INDEX_THRESHOLD:-32m}
#MEMORY_INDEX_MAX=${MEMORY_INDEX_MAX:-512m}
#OBJECT_CACHE_MAX=${OBJECT_CACHE_MAX:-1g}

## Set to false to disable SSL between the peers and the transactor.
ENCRYPT_CHANNEL=${ENCRYPT_CHANNEL:-true}

## Data directory is used for dev: and free: storage, and as a temporary directory for all storages.
DATA_DIR=${DATA_DIR:-/data}

## Transactor will log here, see bin/logback.xml to configure logging.
LOG_DIR=${LOG_DIR:-/var/log/datomic}

# https://docs.datomic.com/on-prem/capacity.html
WRITE_CONCURRENCY=${WRITE_CONCURRENCY:-4}
READ_CONCURRENCY=${READ_CONCURRENCY:-8}
INDEX_PARALLELISM=${INDEX_PARALLELISM:-1}

die() {
  echo
  echo "$*"
  echo
  exit 1
}

if [[ -z "$ALT_HOST" ]]; then
  die "ALT_HOST environment variable must be set"
fi

if [[ -z "$LICENSE_KEY" ]]; then
  die "LICENSE_KEY environment variable must be set"
fi

echo "protocol=$PROTOCOL"
echo "host=$HOST"
echo "port=$PORT"
echo "alt-host=$ALT_HOST"
echo "license-key=$LICENSE_KEY"

echo ""
echo "encrypt-channel=$ENCRYPT_CHANNEL"
echo "data-dir=$DATA_DIR"
echo "log-dir=$LOG_DIR"

echo ""
echo "memory-index-threshold=$MEMORY_INDEX_THRESHOLD"
echo "memory-index-max=$MEMORY_INDEX_MAX"
echo "object-cache-max=$OBJECT_CACHE_MAX"

echo ""
echo "write-concurrency=$WRITE_CONCURRENCY"
echo "read-concurrency=$READ_CONCURRENCY"
echo "index-parallelism=$INDEX_PARALLELISM"

if [[ "$PROTOCOL" == "dev" ]]; then

  H2_PORT=${H2_PORT:-4335}

  echo ""
  echo "h2-port=$H2_PORT"
  echo "storage-admin-password=admin"
  echo "storage-datomic-password=datomic"
  echo "storage-access=remote"
fi

if [[ "$PROTOCOL" == "cass" ]]; then

  CASSANDRA_PORT=${CASSANDRA_PORT:-9042}

  if [[ -z "$CASSANDRA_TABLE" ]]; then
    die "CASSANDRA_TABLE environment variable must be set for Cassandra"
  fi

  if [[ -z "$CASSANDRA_HOST" ]]; then
    die "CASSANDRA_HOST environment variable must be set for Cassandra"
  fi

  echo ""
  echo "cassandra-table=$CASSANDRA_TABLE"
  echo "cassandra-host=$CASSANDRA_HOST"
  echo "cassandra-port=$CASSANDRA_PORT"
fi

# See https://docs.datomic.com/on-prem/transactor.html
if [[ -n "$HEALTH_PORT" ]]; then

  HEALTH_PING_CONCURRENCY=${HEALTH_PING_CONCURRENCY:-6}

  echo ""
  echo "ping-host=0.0.0.0"
  echo "ping-port=$HEALTH_PORT"
  # https://forum.datomic.com/t/jetty-max-threads-error-when-enabling-ping-health/603
  echo "ping-concurrency=$HEALTH_PING_CONCURRENCY"
fi
