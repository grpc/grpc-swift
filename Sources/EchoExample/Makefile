
all:
	swift build -c debug --product Echo
	cp .build/debug/Echo .

test:	all
	./Echo serve & /bin/echo $$! > echo.pid
	./Echo get | tee test.out
	./Echo expand | tee -a test.out
	./Echo collect | tee -a test.out
	./Echo update | tee -a test.out
	kill -9 `cat echo.pid`
	diff -u test.out test.gold

project:
	swift package generate-xcodeproj

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Echo google.json
	rm -rf Package.resolved Echo.xcodeproj Echo
