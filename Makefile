build:
	zig build --release=fast

install:
	cp zig-out/bin/showkeys /usr/bin/showkeys
	chmod a+s /usr/bin/showkeys

theme:
	cp themes /usr/share/showkeys/ -r

uninstall:
	-rm /usr/bin/showkeys
	-rm /usr/share/showkeys
