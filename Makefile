help:
	@echo "Usage: make <target>\n\n\
	  p[roject]\t\t\tGenerate the Xcode project with xcodegen\n\
	  l[int-]f[ormat]\tVerify the project is properly formatted\n\
	  f[ormat]\t\t\tReformat files with SwiftFormat\n\
	  test\t\t\t\tRun unit tests\n\
	"


.PHONY: project
p: project
project:
	xcodegen

.PHONY: lint-format
lf: lint-format
lint-format:
	swiftformat --lint .

.PHONY: format
f: format
format:
	swiftformat .

.PHONY: test
test:
	rm -rf ShadowVim.xcodeproj
	xcodebuild test -scheme "ShadowVim-Package" -destination "platform=macOS"
