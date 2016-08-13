TARGET=Client
all:
	swift build

install:
	cp .build/debug/$(TARGET) .

clean :
	rm -rf Packages
	rm -rf .build
	rm -f $(TARGET)
