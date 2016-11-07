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
	"log"

	"crypto/tls"
	"io"

	pb "echo"
	"golang.org/x/net/context"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

const (
	defaultMessage = "hello"
)

func main() {
	var get = flag.Bool("get", false, "call the Get method")
	var update = flag.Bool("update", false, "call the Update method")
	var collect = flag.Bool("collect", false, "call the Collect method")
	var expand = flag.Bool("expand", false, "call the Expand method")
	var count = flag.Int("n", 10, "number of message to send (update and collect only)")
	var message = flag.String("m", defaultMessage, "the message to send")
	var address = flag.String("a", "", "address of the echo server to use")
	var useTLS = flag.Bool("tls", false, "Use tls for connections.")

	flag.Parse()

	// Set up a connection to the server.
	var conn *grpc.ClientConn
	var err error
	if !*useTLS {
		if *address == "" {
			*address = "localhost:8080"
		}
		conn, err = grpc.Dial(*address, grpc.WithInsecure())
	} else {
		if *address == "" {
			*address = "localhost:443"
		}
		conn, err = grpc.Dial(*address,
			grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{
				// remove the following line if the server certificate is signed by a certificate authority
				InsecureSkipVerify: true,
			})))
	}

	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}

	defer conn.Close()
	c := pb.NewEchoClient(conn)
	if *get {
		call_get(c, *message)
	}
	if *update {
		call_update(c, *message, *count)
	}
	if *collect {
		call_collect(c, *message, *count)
	}
	if *expand {
		call_expand(c, *message)
	}
}

func call_get(c pb.EchoClient, message string) {
	// Contact the server and print out its response.
	response, err := c.Get(context.Background(), &pb.EchoRequest{Text: message})
	if err != nil {
		log.Fatalf("could not receive echo: %v", err)
	}
	log.Printf("Received: %s", response.Text)
}

func call_update(c pb.EchoClient, message string, count int) {
	stream, err := c.Update(context.Background())
	if err != nil {
		panic(err)
	}
	waitc := make(chan struct{})
	go func() {
		for {
			in, err := stream.Recv()
			if err == io.EOF {
				// read done.
				close(waitc)
				return
			}
			if err != nil {
				log.Fatalf("Failed to receive an echo : %v", err)
			}
			log.Printf("Received: %s", in.Text)
		}
	}()
	for i := 1; i <= count; i++ {
		var note pb.EchoRequest
		note.Text = fmt.Sprintf("%s %d", message, i)
		if err := stream.Send(&note); err != nil {
			log.Fatalf("Failed to send a message: %v", err)
		}
	}
	stream.CloseSend()
	<-waitc
}

func call_collect(c pb.EchoClient, message string, count int) {
	stream, err := c.Collect(context.Background())
	if err != nil {
		panic(err)
	}
	for i := 1; i <= count; i++ {
		var note pb.EchoRequest
		note.Text = fmt.Sprintf("%s %d", message, i)
		if err := stream.Send(&note); err != nil {
			log.Fatalf("Failed to send a message: %v", err)
		}
	}
	response, err := stream.CloseAndRecv()
	log.Printf("Received: %s", response.Text)
}

func call_expand(c pb.EchoClient, message string) {
	stream, err := c.Expand(context.Background(), &pb.EchoRequest{Text: message})
	if err != nil {
		panic(err)
	}
	waitc := make(chan struct{})
	for {
		in, err := stream.Recv()
		if err == io.EOF {
			// read done.
			close(waitc)
			return
		}
		if err != nil {
			log.Fatalf("Failed to receive an echo : %v", err)
		}
		log.Printf("Received: %s", in.Text)
	}
	<-waitc
}
