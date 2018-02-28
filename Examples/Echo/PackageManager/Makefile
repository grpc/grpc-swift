
all:
	swift build -c release --product Echo
	cp .build/release/Echo .

test:	all
	Echo serve & /bin/echo $$! > echo.pid
	Echo get > test.out
	Echo expand >> test.out
	Echo collect >> test.out
	Echo update >> test.out
	kill -9 `cat echo.pid`
	diff test.out test.gold
	
project:
	swift package generate-xcodeproj

clean :
	rm -rf Packages googleapis .build
	rm -f Package.pins Echo google.json
	rm -rf Package.resolved Echo.xcodeproj Echo
