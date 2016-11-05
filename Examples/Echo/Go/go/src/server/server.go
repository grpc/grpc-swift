// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"strings"

	pb "echo"
	"golang.org/x/net/context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

// [START echoserver]
type EchoServer struct{}

var echoServer EchoServer

// [END echoserver]

// [START get]
func (s *EchoServer) Get(ctx context.Context, r *pb.EchoRequest) (*pb.EchoResponse, error) {
	response := &pb.EchoResponse{}
	response.Text = "Go nonstreaming echo " + r.Text
	fmt.Printf("Get received: %s\n", r.Text)
	return response, nil
}

// [END get]

func (s *EchoServer) Update(stream pb.Echo_UpdateServer) error {
	for {
		in, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}

		response := &pb.EchoResponse{}
		response.Text = "Go streaming echo " + in.Text

		fmt.Printf("Update received: %s\n", in.Text)

		if err := stream.Send(response); err != nil {
			return err
		}
	}
	return nil
}

func (s *EchoServer) Collect(stream pb.Echo_CollectServer) error {
	parts := []string{}
	for {
		in, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		parts = append(parts, in.Text)
	}
	response := &pb.EchoResponse{}
	response.Text = strings.Join(parts, " ")
	if err := stream.SendAndClose(response); err != nil {
		return err
	}
	return nil
}

func (s *EchoServer) Expand(request *pb.EchoRequest, stream pb.Echo_ExpandServer) error {
	fmt.Printf("Expand received: %s\n", request.Text)
	parts := strings.Split(request.Text, " ")

	for _, part := range parts {
		response := &pb.EchoResponse{}
		response.Text = part
		if err := stream.Send(response); err != nil {
			return err
		}
	}

	return nil
}

// [START main]
func main() {
	var useTLS = flag.Bool("tls", false, "Use tls for connections.")

	flag.Parse()

	var err error
	var lis net.Listener
	var grpcServer *grpc.Server
	if !*useTLS {
		lis, err = net.Listen("tcp", ":8080")
		if err != nil {
			log.Fatalf("failed to listen: %v", err)
		}
		grpcServer = grpc.NewServer()
	} else {
		certFile := "ssl.crt"
		keyFile := "ssl.key"
		creds, err := credentials.NewServerTLSFromFile(certFile, keyFile)
		lis, err = net.Listen("tcp", ":443")
		if err != nil {
			log.Fatalf("failed to listen: %v", err)
		}
		grpcServer = grpc.NewServer(grpc.Creds(creds))
	}
	pb.RegisterEchoServer(grpcServer, &echoServer)
	grpcServer.Serve(lis)
}

// [END main]
