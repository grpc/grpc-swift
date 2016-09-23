package main

import (
	"github.com/golang/protobuf/proto"
	"io/ioutil"
	pb "maps"
)

func main() {
	message := pb.MapTest{}
	message.Name = "hello"
	message.Properties = map[string]string{
		"A": "AAAAAAAAAAAAAAAA",
		"B": "BBBBBBBBBBBBBBBB",
		"C": "CCCCCCCCCCCCCCCC",
	}
	message.IntegerProperties = map[int32]int32 {
		1 : 100,
		2 : 200,
		3 : 300,
		4 : 400,
  	}

	data, err := proto.Marshal(&message)
	if err != nil {
		panic(err)
	}
	err = ioutil.WriteFile("maptest.bin", data, 0644)
	if err != nil {
		panic(err)
	}
}
