FROM swiftdocker/swift:latest
MAINTAINER Tim Burks <timburks@google.com>

# Install a few needed packages that aren't in swiftdocker/swift
RUN apt-get -q update && \
    apt-get -q install -y libz-dev && \
    apt-get -q install -y unzip 

# Install protoc
RUN curl -O -L https://github.com/google/protobuf/releases/download/v3.2.0rc2/protoc-3.2.0rc2-linux-x86_64.zip && \
    unzip protoc-3.2.0rc2-linux-x86_64.zip -d /usr

# Build and install the swiftgrpc plugin
RUN git clone https://github.com/grpc/grpc-swift && \
    cd grpc-swift/Plugin && \
    make && \
    cp protoc-gen-swift /usr/bin && \
    cp protoc-gen-swiftgrpc /usr/bin 

