# Swift gRPC Base Image

Use the Dockerfile in this directory to build a Docker image 
that's preloaded with the Swift gRPC plugin and related tools.

Build with the following command:

    docker build -t grpc/swift .

The following commands push the image to Google Container Registry.

    docker tag grpc/swift gcr.io/swift-services/grpc
    gcloud docker -- push gcr.io/swift-services/grpc


