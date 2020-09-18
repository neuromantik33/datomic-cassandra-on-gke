FROM openjdk:11
ARG version

ENV DATOMIC_HOME=/opt/datomic-pro-$version \
    DATOMIC_LOG_DIR=/var/log/datomic

ADD datomic-pro-$version.zip /tmp
RUN set -o errexit -o nounset \
    \
    && echo "Installing build dependencies" \
    && apt-get update \
    && apt-get install --yes --no-install-recommends \
        unzip \
    && rm --recursive --force /var/lib/apt/lists/* \
    && unzip -n /tmp/datomic-pro-$version.zip -d /opt/ \
    && rm -rf /tmp/datomic-pro-$version.zip \
    && mkdir $DATOMIC_HOME/data \
    && echo "Cleaning up build dependencies" \
    && echo $(apt-mark showauto) \
    && apt-get remove --yes --purge \
        unzip \
    && apt-get autoremove --yes --purge

ADD peer.sh \
    transactor.sh \
    xactor_properties.sh \
    logback.xml \
    $DATOMIC_HOME/bin/
WORKDIR $DATOMIC_HOME
EXPOSE 4334 4335 4336 8998
