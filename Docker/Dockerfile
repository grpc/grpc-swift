FROM swift:latest as development
LABEL maintainer="Tim Burks <timburks@google.com>"

ENV PROTOC_VERSION=3.9.1

# Install a few missing packages
RUN apt-get -q update \
    && apt-get -q install -y curl unzip libz-dev libssl-dev libnghttp2-dev \
    && rm -r /var/lib/apt/lists/*

# Install protoc
RUN curl -O -L https://github.com/google/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip \
    && unzip protoc-${PROTOC_VERSION}-linux-x86_64.zip -d /usr \
    && rm -rf protoc-${PROTOC_VERSION}-linux-x86_64.zip

# Build and install the swiftgrpc plugin
RUN git clone https://github.com/grpc/grpc-swift \
    && cd grpc-swift \
    && make test-plugin && make plugin \
    && cp protoc-gen-swift protoc-gen-swiftgrpc /usr/bin


FROM swift:slim as protoc-runner
# copy protoc and plugins binaries
COPY --from=development /usr/bin/protoc /usr/bin/protoc-gen-swift /usr/bin/protoc-gen-swiftgrpc /usr/bin/
# copy .proto well known types
COPY --from=development /usr/include/google/ /usr/include/google/