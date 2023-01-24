help:
	@echo "Usage: make <target>\n\n\
	  project\t\tGenerate the Xcode project with xcodegen\n\
	  lint-format\t\tVerify the project is properly formatted\n\
	  format\t\tReformat files with SwiftFormat\n\
	"

.PHONY: project
project:
	xcodegen

.PHONY: lint-format
lint-format:
	swiftformat --lint .

.PHONY: format
format:
	swiftformat .
