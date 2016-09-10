package main

import (
	"github.com/golang/protobuf/proto"
	"io/ioutil"
	pb "sample"
)

func main() {
	inner := pb.SampleMessage{}
	inner.Text = "ABCDEFG"
	inner.B = false
	inner.Si32 = -1234
	inner.Si64 = -1234567

	message := pb.SampleMessage{}
	message.D = 1.23
	message.F = 4.56
	message.I64 = 1234567
	message.Ui64 = 1234567
	message.I32 = 1234
	message.F64 = 1234567
	message.F32 = 1234
	message.B = true
	message.Text = "Hello, world!"
	//message.Data = 
	message.Ui32 = 1234
	message.Sf32 = 1234
	message.Sf64 = 1234567
	message.Si32 = 1234
	message.Si64 = 1234567
	message.Message = &inner

	data, err := proto.Marshal(&message)
	if err != nil {
		panic(err)
	}
	err = ioutil.WriteFile("SampleMessage.bin", data, 0644)
	if err != nil {
		panic(err)
	}
}
