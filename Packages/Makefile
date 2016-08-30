
demo: 	
	cd CgRPC; make clean; make; cd ..
	cd gRPC; make clean; make; cd ..
	cd Server; make clean; make; make; make install; cd ..
	cd Client; make clean; make; make; make install; cd ..
	cd QuickProto; make clean; make; make; make install; cd ..
	cd EchoServer; make clean; make; make; make install; cd ..
	cd EchoClient; make clean; make; make; make install; cd ..
	EchoServer/EchoServer &
	EchoClient/EchoClient 

clean:  
	cd CgRPC; make clean; cd ..
	cd gRPC; make clean; cd ..
	cd Server; make clean; cd ..
	cd Client; make clean; cd ..
	cd QuickProto; make clean; cd ..
	cd EchoServer; make clean; cd ..
	cd EchoClient; make clean; cd ..
