#!/bin/bash

set -e

cd $(dirname $0)/..

while [ $# -gt 1 ]
do
    case "$1" in
        -Xmx*)
            XMX=$1
            ;;
        -Xms*)
            XMS=$1
            ;;
        *)
            JAVA_OPTS="$JAVA_OPTS $1"
            ;;
    esac
    shift
done

# defaults
if [ "$XMX" == "" ]; then
    XMX=-Xmx1g
fi
if [ "$XMS" == "" ]; then
    XMS=-Xms1g
fi
if [ "$JAVA_OPTS"  == "" ]; then
    JAVA_OPTS='-XX:MaxGCPauseMillis=50'
fi

# Create the transactor properties file if it doesn't exist
TRANSACTOR_PROPS=config/transactor.properties
if [ ! -f ${TRANSACTOR_PROPS} ]; then
  bin/xactor_properties.sh >>${TRANSACTOR_PROPS}
  echo "Generated properties file : $(cat ${TRANSACTOR_PROPS})"
fi

echo "Launching with Java options -server $XMS $XMX $JAVA_OPTS"
exec java -server -cp $(bin/classpath) $XMX $XMS "$JAVA_OPTS" clojure.main --main datomic.launcher $TRANSACTOR_PROPS
