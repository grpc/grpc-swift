TARGET=Client

UNAME := $(shell uname)

ifeq ($(UNAME), Darwin)
LIBDIR = ../../third_party/grpc/libs/opt
INCDIR = ../../third_party/grpc/include
endif

ifeq ($(UNAME), Linux)
LIBDIR = /usr/local/lib
INCDIR = /usr/local/include
endif

all:
	swift build -Xlinker -L$(LIBDIR) -Xlinker -lgrpc -Xcc -I$(INCDIR)

install: all
	cp .build/debug/$(TARGET) .

clean :
	rm -rf Packages
	rm -rf .build
	rm -f $(TARGET)
