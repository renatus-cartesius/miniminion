FROM ubuntu:24.04

ARG UID=1000
ARG GID=1000

RUN if getent passwd ${UID}; then userdel -f -r $(getent passwd ${UID} | cut -d: -f1); fi && \
    if getent group ${GID}; then groupdel $(getent group ${GID} | cut -d: -f1); fi

RUN apt-get update && apt-get install -y \
    libjsonnet-dev \
    curl \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt && \
    curl -L https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz -o /opt/zig.tar.xz && \
    tar -xf /opt/zig.tar.xz -C /opt && \
    mv /opt/zig-x86_64-linux-0.16.0 /opt/zig && \
    rm /opt/zig.tar.xz

RUN groupadd -g ${GID} developer && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash developer

ENV PATH=/opt/zig:$PATH

USER developer

