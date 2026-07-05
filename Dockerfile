FROM alpine:3.21

ARG UID=1000
ARG GID=1000

RUN apk add --no-cache \
    curl \
    xz \
    git \
    g++ \
    clang \
    llvm \
    make \
    cmake \
    linux-headers \
    libbpf-dev

RUN mkdir -p /opt && \
    curl -L https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz -o /opt/zig.tar.xz && \
    tar -xf /opt/zig.tar.xz -C /opt && \
    mv /opt/zig-x86_64-linux-0.16.0 /opt/zig && \
    rm /opt/zig.tar.xz

RUN git clone --depth=1 https://github.com/google/jsonnet.git /opt/jsonnet && \
    cmake -S /opt/jsonnet -B /opt/jsonnet/build \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release && \
    make -C /opt/jsonnet/build -j$(nproc) && \
    mkdir -p /opt/jsonnet-dist/lib /opt/jsonnet-dist/include && \
    cp /opt/jsonnet/build/libjsonnet.a /opt/jsonnet-dist/lib/ && \
    cp /opt/jsonnet/include/libjsonnet.h /opt/jsonnet-dist/include/ && \
    cp /opt/jsonnet/include/libjsonnet++.h /opt/jsonnet-dist/include/ && \
    cp $(g++ --print-file-name=libstdc++.a) /opt/jsonnet-dist/lib/ && \
    cp $(g++ --print-file-name=libgcc_eh.a) /opt/jsonnet-dist/lib/

RUN addgroup -g ${GID} developer && \
    adduser -u ${UID} -G developer -s /bin/bash -D developer

ENV PATH=/opt/zig:$PATH

USER developer