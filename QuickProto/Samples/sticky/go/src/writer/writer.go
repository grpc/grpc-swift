package main

import (
	"github.com/golang/protobuf/proto"
	"io/ioutil"
	pb "messagepb"
)

func main() {
	request := &pb.StickyNoteRequest{}
	request.Message = "hello, world"
	data, err := proto.Marshal(request)
	if err != nil {
		panic(err)
	}
	err = ioutil.WriteFile("StickyNoteRequest.bin", data, 0644)
	if err != nil {
		panic(err)
	}
}
