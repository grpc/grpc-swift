LIBDIR = /usr/local/lib
INCDIR = /usr/local/include

all:
	swift build -Xlinker -L$(LIBDIR) -Xlinker -lgrpc -Xcc -I$(INCDIR)

clean :
	rm -rf Packages
	rm -rf .build
