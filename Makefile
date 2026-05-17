build:
	zig build --release=fast

install: build
	sudo cp zig-out/bin/showkeys /usr/bin/showkeys
	sudo chmod a+s /usr/bin/showkeys
