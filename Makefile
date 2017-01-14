LIBDIR = /usr/local/lib
INCDIR = /usr/local/include

test:
	swift build -Xlinker -L$(LIBDIR) -Xlinker -lgrpc -Xcc -I$(INCDIR)
	swift test -Xlinker -L$(LIBDIR) -Xlinker -lgrpc -Xcc -I$(INCDIR)

clean :
	rm -rf Packages
	rm -rf .build
