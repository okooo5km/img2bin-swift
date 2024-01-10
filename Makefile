install:
	swift build -c release
	install .build/release/img2bin ~/.local/bin/img2bin
