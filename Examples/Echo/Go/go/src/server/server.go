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
	"time"

	pb "echo"
	"golang.org/x/net/context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

type EchoServer struct{}

var echoServer EchoServer

// requests are immediately returned, no inbound or outbound streaming
func (s *EchoServer) Get(ctx context.Context, request *pb.EchoRequest) (*pb.EchoResponse, error) {
	fmt.Printf("Get received: %s\n", request.Text)
	response := &pb.EchoResponse{}
	response.Text = "Go echo get: " + request.Text
	return response, nil
}

// requests stream in and are immediately streamed out
func (s *EchoServer) Update(stream pb.Echo_UpdateServer) error {
	count := 0
	for {
		request, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		fmt.Printf("Update received: %s\n", request.Text)
		response := &pb.EchoResponse{}
		response.Text = fmt.Sprintf("Go echo update (%d): %s", count, request.Text)
		count++
		if err := stream.Send(response); err != nil {
			return err
		}
	}
	return nil
}

// requests stream in, are appended together, and are returned in a single response when the input is closed
func (s *EchoServer) Collect(stream pb.Echo_CollectServer) error {
	parts := []string{}
	for {
		request, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		fmt.Printf("Collect received: %s\n", request.Text)
		parts = append(parts, request.Text)
	}
	response := &pb.EchoResponse{}
	response.Text = fmt.Sprintf("Go echo collect: %s", strings.Join(parts, " "))
	if err := stream.SendAndClose(response); err != nil {
		return err
	}
	return nil
}

// a single request is accepted and split into parts which are individually returned with a time delay
func (s *EchoServer) Expand(request *pb.EchoRequest, stream pb.Echo_ExpandServer) error {
	fmt.Printf("Expand received: %s\n", request.Text)
	parts := strings.Split(request.Text, " ")
	for i, part := range parts {
		response := &pb.EchoResponse{}
		response.Text = fmt.Sprintf("Go echo expand (%d): %s", i, part)
		if err := stream.Send(response); err != nil {
			return err
		}
		time.Sleep(1 * time.Second)
	}
	return nil
}

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
