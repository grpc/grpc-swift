# Swift gRPC in Docker

Swift gRPC works great within Docker. Use the Dockerfile in this directory to build a Docker image that's preloaded with the Swift gRPC plugin and related tools.

## Prerequisites

- [Docker](https://www.docker.com)
  - [Docker for Mac](https://hub.docker.com/editions/community/docker-ce-desktop-mac)
  - [Docker for Windows](https://hub.docker.com/editions/community/docker-ce-desktop-windows)
  - [Docker for Ubuntu](https://hub.docker.com/editions/community/docker-ce-server-ubuntu)
  - [Docker for Debian](https://hub.docker.com/editions/community/docker-ce-server-debian)
  - [Docker for CentOS](https://hub.docker.com/editions/community/docker-ce-server-centos)
  - [Docker for Fedora](https://hub.docker.com/editions/community/docker-ce-server-fedora)

## Development environment

Build the Docker image with the following command:

```bash
docker build -t grpc/swift --target development .
```

Run docker container with the following command:

```bash
docker run -it --privileged=true grpc/swift /bin/bash
```

Run the grpc-swift unit tests:

```bash
cd grpc-swift
make test
```

Run the test client and server:

```bash
# start the server
.build/debug/Echo serve &
# run the client to test each Echo API
.build/debug/Echo get
.build/debug/Echo expand
.build/debug/Echo collect
.build/debug/Echo update
#stop the server
kill -9 `pgrep Echo`
```

## Protoc-runner

Build docker image with the following command:

```bash
docker build -t protoc-runner .
```

If you plan only to use `protoc` with plugins - run `docker image prune` to remove intermediate images.

To run protoc-runner container, open folder with your `.proto` files in terminal and use following command:

```bash
docker run --name protoc -v `pwd`:/work_dir -w /work_dir protoc-runner \
protoc --swift_out=. --swiftgrpc_out=. *.proto
```

- `--name protoc` - container name
- ``-v `pwd`:/work_dir`` - map current directory to container's `/work_dir`
- `-w /work_dir` - set container's working directory
- `protoc-runner` - docker image name
- `protoc --swift_out=. --swiftgrpc_out=. *.proto` - command that will be run after container start

To restart `protoc` start protoc container again:

```bash
docker start protoc
```

## Google Container Registry

The following commands push the image to Google Container Registry.

```bash
docker tag grpc/swift gcr.io/swift-services/grpc
gcloud docker -- push gcr.io/swift-services/grpc
```
