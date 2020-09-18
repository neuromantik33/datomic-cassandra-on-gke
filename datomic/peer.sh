#!/usr/bin/env sh

##############################################################################
##
##  datomic peer start up script for UN*X
##
##############################################################################

set -e

# Attempt to set APP_HOME
# Resolve links: $0 may be a link
PRG="$0"
# Need this for relative symlinks.
while [ -h "$PRG" ]; do
  ls=$(ls -ld "$PRG")
  link=$(expr "$ls" : '.*-> \(.*\)$')
  if expr "$link" : '/.*' >/dev/null; then
    PRG="$link"
  else
    PRG=$(dirname "$PRG")"/$link"
  fi
done
SAVED="$(pwd)"
cd "$(dirname \"$PRG\")/.." >/dev/null
APP_HOME="$(pwd -P)"
cd ${APP_HOME} >/dev/null

# Add default JVM options here. You can also use JAVA_OPTS to pass JVM options to this script.
DEFAULT_JVM_OPTS='-XX:+ExitOnOutOfMemoryError'

JAVA_OPTS=${JAVA_OPTS:-"-server -XX:+UseStringDeduplication"}

GC_OPTS=${GC_OPTS:-"-XX:+UseG1GC"}

# https://www.ibm.com/developerworks/community/blogs/kevgrig/entry/linux_glibc_2_10_rhel_6_malloc_may_show_excessive_virtual_memory_usage?lang=en
export MALLOC_ARENA_MAX=${MALLOC_ARENA_MAX:-4}

# Use the maximum available, or set MAX_FD != -1 to use that value.
MAX_FD="maximum"

warn() {
  echo "$*"
}

die() {
  echo
  echo "$*"
  echo
  exit 1
}

CLASSPATH=$("$APP_HOME/bin/classpath")

# Determine the Java command to use to start the JVM.
if [ -n "$JAVA_HOME" ]; then
  if [ -x "$JAVA_HOME/jre/sh/java" ]; then
    # IBM's JDK on AIX uses strange locations for the executables
    JAVACMD="$JAVA_HOME/jre/sh/java"
  else
    JAVACMD="$JAVA_HOME/bin/java"
  fi
  if [ ! -x "$JAVACMD" ]; then
    die "ERROR: JAVA_HOME is set to an invalid directory: $JAVA_HOME

Please set the JAVA_HOME variable in your environment to match the
location of your Java installation."
  fi
else
  JAVACMD="java"
  which java >/dev/null 2>&1 || die "ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.

Please set the JAVA_HOME variable in your environment to match the
location of your Java installation."
fi

# Increase the maximum file descriptors if we can.
MAX_FD_LIMIT=$(ulimit -H -n)
if [ $? -eq 0 ]; then
  if [ "$MAX_FD" = "maximum" -o "$MAX_FD" = "max" ]; then
    MAX_FD="$MAX_FD_LIMIT"
  fi
  ulimit -n ${MAX_FD}
  if [ $? -ne 0 ]; then
    warn "Could not set maximum file descriptor limit: $MAX_FD"
  fi
else
  warn "Could not query maximum file descriptor limit: $MAX_FD_LIMIT"
fi

# Extract the environment variables to later inject as command line arguments: idiomatic Docker :)
APP_ARGS="-m datomic.peer-server"

# If the max heap size is not specifically set, calculate it based on the container's cgroup limits
ALL_JVM_OPTS="$DEFAULT_JVM_OPTS $JAVA_OPTS $GC_OPTS"

# Mandatory env variables
[ -z "$PEER_ACCESS_KEY" ] && die "PEER_ACCESS_KEY environment variable must be set"
[ -z "$PEER_SECRET" ] && die "PEER_SECRET environment variable must be set"
[ -z "$PEER_DB_NAME" ] && die "PEER_DB_NAME environment variable must be set"
[ -z "$PEER_DB_URI" ] && die "PEER_DB_URI environment variable must be set"
APP_ARGS="$APP_ARGS --host 0.0.0.0 --port 8998 --auth $PEER_ACCESS_KEY,$PEER_SECRET --db $PEER_DB_NAME,$PEER_DB_URI"

# Collect all arguments for the java command, following the shell quoting and substitution rules
eval set -- "$ALL_JVM_OPTS -classpath \"$CLASSPATH\" clojure.main -i bin/bridge.clj $APP_ARGS"

echo "Executing : $JAVACMD $@"
exec "$JAVACMD" "$@"
