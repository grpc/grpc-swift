#!/bin/sh
#
# Run this for a basic sanity check of the Swift gRPC packages
#
cd CgRPC; make clean; make; cd ..
cd gRPC; make clean; make; cd ..
cd Server; make clean; make; make; make install; cd ..
cd Client; make clean; make; make; make install; cd ..
Server/Server &
Client/Client 
