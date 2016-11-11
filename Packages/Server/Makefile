TARGET=Server
all:
	swift build -Xlinker -L/usr/local/lib

install:
	cp .build/debug/$(TARGET) .

clean :
	rm -rf Packages
	rm -rf .build
	rm -f $(TARGET)
