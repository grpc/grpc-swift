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
	useSSL         = false
	defaultMessage = "hello"
)

func main() {

	var stream = flag.Int("s", 0, "send multiple messages by streaming")
	var message = flag.String("m", defaultMessage, "the message to send")
	var address = flag.String("a", "", "address of the echo server to use")

	flag.Parse()

	// Set up a connection to the server.
	var conn *grpc.ClientConn
	var err error
	if !useSSL {
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

	if *stream > 0 {
		send_many_messages(c, *message, *stream)
	} else {
		send_one_message(c, *message)
	}
}

func send_one_message(c pb.EchoClient, message string) {
	// Contact the server and print out its response.
	response, err := c.Get(context.Background(), &pb.EchoRequest{Text: message})
	if err != nil {
		log.Fatalf("could not receive echo: %v", err)
	}
	log.Printf("Received: %s", response.Text)
}

func send_many_messages(c pb.EchoClient, message string, count int) {
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
			count = count + 1
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
