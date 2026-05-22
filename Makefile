build:
	zig build -Doptimize=ReleaseFast

install:
	cp zig-out/bin/showkeys /usr/bin/showkeys
	chmod a+s /usr/bin/showkeys

uninstall:
	-rm /usr/bin/showkeys
