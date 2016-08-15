
all: 	
	cd CgRPC; make clean; make; cd ..
	cd gRPC; make clean; make; cd ..
	cd Server; make clean; make; make; make install; cd ..
	cd Client; make clean; make; make; make install; cd ..
	Server/Server &
	Client/Client 

clean:  
	cd CgRPC; make clean; cd ..
	cd gRPC; make clean; cd ..
	cd Server; make clean; cd ..
	cd Client; make clean; cd ..
