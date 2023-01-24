help:
	@echo "Usage: make <target>\n\n\
	  project\t\tGenerate the Xcode project with xcodegen\n\
	  format\t\tReformat files with SwiftFormat\n\
	"

.PHONY: project
project:
	xcodegen

.PHONY: format
format:
	swiftformat .
