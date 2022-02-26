

ARG JDIST=jdk
ARG JAVA_MAJOR=11
ARG DISTRIB_NAME=ubi
ARG DISTRIB_MAJOR=8
ARG TOMCAT_MAJOR=9


FROM openjdk:11.0.13-oraclelinux8 AS ubi8
ARG JAVA_MAJOR
ENV BUILD_DEP="gzip gcc make openssl-devel expat-devel"
USER root
RUN microdnf --setopt=install_weak_deps=0 --setopt=tsflags=nodocs install -y $BUILD_DEP java-${JAVA_MAJOR}-openjdk-devel

FROM $DISTRIB_NAME${DISTRIB_MAJOR} AS tomcat9
ENV TOMCAT_MAJOR 9
ENV TOMCAT_VERSION 9.0.54
ENV TOMCAT_SHA512 83430f24d42186ce2ff51eeef2f7a5517048f37d9050c45cac1e3dba8926d61a1f7f5aba122a34a11ac1dbdd3c1f6d98671841047df139394d43751263de57c3

FROM $DISTRIB_NAME${DISTRIB_MAJOR} AS TCNATIVE_BUILD
ARG TCNATIVE_VERSION=1.2.31
ARG TCNATIVE_SHA512=2aaa93f0acf3eb780d39faeda3ece3cf053d3b6e2918462f7183070e8ab32232e035e9062f7c07ceb621006d727d3596d9b4b948f4432b4f625327b72fdb0e49
ARG APR_VERSION=1.7.0
ARG APR_SHA256=48e9dbf45ae3fdc7b491259ffb6ccf7d63049ffacbc1c0977cced095e4c2d5a2
ARG APR_UTIL_VERSION=1.6.1
ARG APR_UTIL_SHA256=b65e40713da57d004123b6319828be7f1273fbc6490e145874ee1177e112c459
ENV BUILD_DIR=/build
ENV INSTALL_DIR=/usr/local
ENV APACHE_MIRRORS \
        https://www.apache.org/dyn/closer.cgi?action=download&filename= \
        https://archive.apache.org/dist \
        https://www-us.apache.org/dist \
        https://www.apache.org/dist
SHELL ["/bin/bash","-c"]
RUN mkdir -p {${INSTALL_DIR},${BUILD_DIR}}/{tcnative,libapr,apr-util}
WORKDIR $BUILD_DIR
RUN set -eux; \
        for mirror in $APACHE_MIRRORS; do \
	        if curl -fsSL ${mirror}/tomcat/tomcat-connectors/KEYS | gpg --import; then \
			curl -fsSL ${mirror}/apr/KEYS | gpg --import; \
			active_mirror=$mirror; \
			break; \
		fi; \
	done; \
	[ -n "active_mirror" ]; \
	\
	for filetype in '.tar.gz' '.tar.gz.asc'; do \
		curl -fsSLo tcnative-${TCNATIVE_VERSION}-src${filetype} "${active_mirror}/tomcat/tomcat-connectors/native/${TCNATIVE_VERSION}/source/tomcat-native-${TCNATIVE_VERSION}-src${filetype}"; \
		curl -fsSLo apr-${APR_VERSION}${filetype} "${active_mirror}/apr/apr-${APR_VERSION}${filetype}"; \
		curl -fsSLo apr-util-${APR_VERSION}${filetype} "${active_mirror}/apr/apr-util-${APR_UTIL_VERSION}${filetype}"; \
	done; \
	\
	echo "$TCNATIVE_SHA512 *tcnative-${TCNATIVE_VERSION}-src.tar.gz" | sha512sum -c -; \
	echo "$APR_SHA256 *apr-${APR_VERSION}.tar.gz" | sha256sum -c -; \
	echo "$APR_UTIL_SHA256 *apr-util-${APR_VERSION}.tar.gz" | sha256sum -c -; \
	\
	gpg --verify tcnative-${TCNATIVE_VERSION}-src.tar.gz.asc && \
        tar -zxf tcnative-${TCNATIVE_VERSION}-src.tar.gz --strip-components=1 -C ${BUILD_DIR}/tcnative; \
	if gpg --verify apr-${APR_VERSION}.tar.gz.asc; then \
		echo signature checked; \
	else \
		keyID=$(gpg --verify apr-${APR_VERSION}.tar.gz.asc 2>&1 | awk '/RSA\ /{print $NF}'); \
		gpg --keyserver pgp.mit.edu --recv-keys "0x$keyID"; \
		gpg --verify apr-${APR_VERSION}.tar.gz.asc; \
	fi && \
        tar -zxf apr-${APR_VERSION}.tar.gz --strip-components=1 -C ${BUILD_DIR}/libapr; \
	if gpg --verify apr-util-${APR_VERSION}.tar.gz.asc; then \
		echo signature checked; \
	else \
		keyID=$(gpg --batch --verify apr-util-${APR_VERSION}.tar.gz.asc 2>&1 | awk '/RSA\ /{print $NF}'); \
		gpg --keyserver pgp.mit.edu --recv-keys "0x$keyID"; \
		gpg --verify apr-util-${APR_VERSION}.tar.gz.asc; \
	fi && \
        tar -zxf apr-util-${APR_VERSION}.tar.gz --strip-components=1 -C ${BUILD_DIR}/apr-util
WORKDIR ${BUILD_DIR}/libapr
RUN ./configure --prefix=${INSTALL_DIR}/apr  && make && make install
WORKDIR ${BUILD_DIR}/apr-util
RUN ./configure  --prefix=${INSTALL_DIR}/apr --with-apr=${INSTALL_DIR}/apr && make && make install
WORKDIR ${BUILD_DIR}/tcnative/native
RUN ./configure \
        --with-java-home="$JAVA_HOME" \
        --libdir="${INSTALL_DIR}/tcnative" \
	--with-apr="${INSTALL_DIR}/apr" \
        --with-ssl=yes; \
    make -j "$(nproc)"; \
    make install;

FROM tomcat${TOMCAT_MAJOR} AS TOMCAT_BUILD
RUN mkdir -p /build
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR
ENV TOMCAT_TGZ_URLS \
	https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
	https://www-us.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
	https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
	https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz
ENV TOMCAT_ASC_URLS \
	https://www.apache.org/dyn/closer.cgi?action=download&filename=tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc \
	https://www-us.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc \
	https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc \
	https://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc
RUN set -eux; \
	curl -fsSL https://www.apache.org/dist/tomcat/tomcat-${TOMCAT_MAJOR}/KEYS | gpg --import; \
	success=; \
	for url in $TOMCAT_TGZ_URLS; do \
		if curl -fsSLo tomcat.tar.gz "$url"; then \
			success=1; \
			break; \
		fi; \
	done; \
	[ -n "$success" ]; \
	\
	echo "$TOMCAT_SHA512 *tomcat.tar.gz" | sha512sum -c -; \
	\
	success=; \
	for url in $TOMCAT_ASC_URLS; do \
		if curl -fsSLo tomcat.tar.gz.asc "$url"; then \
			success=1; \
			break; \
		fi; \
	done; \
	[ -n "$success" ]; \
	\
	gpg --batch --verify tomcat.tar.gz.asc tomcat.tar.gz && \
	tar -zxf tomcat.tar.gz -C /build --strip-components=1

WORKDIR /build
RUN \
	find ./bin/ -name '*.sh' -exec sed -ri 's|^#!/bin/sh$|#!/usr/bin/env bash|' '{}' +; \
	\
	chmod -R +rX .; \
	chmod 770 logs work ; \
	\
	sed -i \
          -e "s/\  <Listener\ className=\"org.apache.catalina.startup.VersionLoggerListener\"/\  <Listener\ className=\"org.apache.catalina.startup.VersionLoggerListener\"\ logArgs=\"false\"/g" \
          -e "s%\(^\s*</Host>\)%\t<Valve className=\"org.apache.catalina.valves.RemoteIpValve\" />\n\n\1%" \
          -e "s/\    <Connector\ port=\"8080\"\ protocol=\"HTTP\/1.1\"/\    <Connector\ port=\"8080\"\ protocol=\"HTTP\/1.1\"\n\               Server=\" \"/g" conf/server.xml; \
	rm -f -r -d webapps/* ; \
	sed -i "$ d" conf/web.xml ; \
	sed -i -e "\$a\    <error-page\>\n\        <error-code\>404<\/error-code\>\n\        <location\>\/error.jsp<\/location\>\n\    <\/error-page\>\n\    <error-page\>\n\        <error-code\>403<\/error-code\>\n\        <location\>\/error.jsp<\/location\>\n\    <\/error-page\>\n\    <error-page\>\n\        <error-code\>500<\/error-code\>\n\        <location\>\/error.jsp<\/location\>\n\    <\/error-page\>\n\n\<\/web-app\>" conf/web.xml 

FROM openjdk:11.0.13-oraclelinux8 AS TOMCAT_BASE_IMAGE
ARG JAVA_MAJOR
ARG DISTRIB_MAJOR
ARG CREATED
ARG REVISION
LABEL org.label-schema.schema-version="1.0" \
	org.label-schema.name="Alfresco Base Tomcat Image" \
	org.label-schema.vendor="Alfresco" \
	org.label-schema.build-date="$CREATED" \
	org.opencontainers.image.title="Alfresco Base Tomcat Image" \
	org.opencontainers.image.vendor="Alfresco" \
	org.opencontainers.image.revision="$REVISION" \
	org.opencontainers.image.source="https://github.com/Alfresco/alfresco-docker-base-tomcat" \
	org.opencontainers.image.created="$CREATED"
ENV CATALINA_HOME /usr/local/tomcat
ENV TOMCAT_NATIVE_LIBDIR $CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR
ENV PATH $CATALINA_HOME/bin:$PATH
WORKDIR $CATALINA_HOME
COPY --from=TOMCAT_BUILD /build $CATALINA_HOME
COPY --from=TCNATIVE_BUILD /usr/local/apr /usr/local/apr
COPY --from=TCNATIVE_BUILD /usr/local/tcnative $TOMCAT_NATIVE_LIBDIR
USER root
RUN set -e \
	echo -e "/usr/local/apr/lib\n$TOMCAT_NATIVE_LIBDIR" >> /etc/ld.so.conf.d/tomcat.conf; \
	nativeLines="$(catalina.sh configtest 2>&1 | grep -c 'Loaded Apache Tomcat Native library')" && \
	test $nativeLines -ge 1 || exit 1
EXPOSE 8080
CMD ["catalina.sh", "run", "-security"]