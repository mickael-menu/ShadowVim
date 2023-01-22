help:
	@echo "Usage: make <target>\n\n\
	  format\t\tReformat files with SwiftFormat\n\
	"

.PHONY: format
format:
	swiftformat .
