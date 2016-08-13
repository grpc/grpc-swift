#!/bin/sh
#
# Run this to clean up all Swift gRPC packages
#
cd CgRPC; make clean; cd ..
cd gRPC; make clean; cd ..
cd Server; make clean; cd ..
cd Client; make clean; cd ..
