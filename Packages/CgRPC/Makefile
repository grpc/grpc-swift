SRCDIR = Sources
SHAREDLIB = libCgRPC.so

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
        SHAREDLIBPATH = /usr/lib
endif
ifeq ($(UNAME_S),Darwin)
        SHAREDLIBPATH = /usr/local/lib
endif

gRPC_Core: $(SRCDIR)/byte_buffer.c $(SRCDIR)/call.c $(SRCDIR)/channel.c $(SRCDIR)/completion_queue.c $(SRCDIR)/event.c $(SRCDIR)/handler.c $(SRCDIR)/internal.c $(SRCDIR)/metadata.c $(SRCDIR)/mutex.c $(SRCDIR)/observers.c $(SRCDIR)/server.c $(SRCDIR)/operations.c
	clang -I../../third_party/grpc/include -shared -fPIC -o $(SHAREDLIB) $(SRCDIR)/byte_buffer.c $(SRCDIR)/call.c $(SRCDIR)/channel.c $(SRCDIR)/completion_queue.c $(SRCDIR)/event.c $(SRCDIR)/handler.c $(SRCDIR)/internal.c $(SRCDIR)/metadata.c $(SRCDIR)/mutex.c $(SRCDIR)/observers.c $(SRCDIR)/server.c $(SRCDIR)/operations.c -lgrpc -L../../third_party/grpc/libs/opt
	cp $(SHAREDLIB) $(SHAREDLIBPATH)
	git init ; git add . ; git commit -m "Commit" ; git tag 1.0.0

clean:
	-rm -f $(SHAREDLIB)
	-rm -f $(SHAREDLIBPATH)/$(SHAREDLIB)
	-rm -rf .git

