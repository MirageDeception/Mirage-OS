BINARY     := mirage
BUILD_DIR  := ./build
CMD_PATH   := ./cmd/mirage

# Build-time vars injected via ldflags
VERSION    := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT     := $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
BUILDDATE  := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
LDFLAGS    := -ldflags "\
	-X github.com/mirage-security/mirage/internal/cmd.Version=$(VERSION) \
	-X github.com/mirage-security/mirage/internal/cmd.Commit=$(COMMIT) \
	-X github.com/mirage-security/mirage/internal/cmd.BuildDate=$(BUILDDATE) \
	-s -w"

.PHONY: build clean test lint run install release cross-compile help

## build: Compile mirage binary for the current OS/arch
build:
	@echo "Building $(BINARY) $(VERSION)..."
	@mkdir -p $(BUILD_DIR)
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY) $(CMD_PATH)
	@echo "✓ Build complete: $(BUILD_DIR)/$(BINARY)"

## install: Install to $GOPATH/bin (or ~/go/bin)
install:
	go install $(LDFLAGS) $(CMD_PATH)
	@echo "✓ Installed: $(shell go env GOPATH)/bin/$(BINARY)"

## run: Build and run with --help
run: build
	$(BUILD_DIR)/$(BINARY) --help

## test: Run all unit tests
test:
	go test -v -race -timeout 30s ./...

## test-cover: Run tests with coverage report
test-cover:
	go test -v -race -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "✓ Coverage report: coverage.html"

## lint: Run golangci-lint
lint:
	@which golangci-lint > /dev/null || (echo "Installing golangci-lint..."; go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest)
	golangci-lint run ./...

## vet: Run go vet
vet:
	go vet ./...

## tidy: Tidy go.mod/go.sum
tidy:
	go mod tidy

## cross-compile: Build for all target platforms
cross-compile:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux   GOARCH=amd64  go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-amd64   $(CMD_PATH)
	GOOS=darwin  GOARCH=amd64  go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-darwin-amd64  $(CMD_PATH)
	GOOS=darwin  GOARCH=arm64  go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-darwin-arm64  $(CMD_PATH)
	GOOS=windows GOARCH=amd64  go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY)-windows-amd64.exe $(CMD_PATH)
	@echo "✓ Cross-compile complete:"
	@ls -lh $(BUILD_DIR)/

## clean: Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)/ coverage.out coverage.html
	@echo "✓ Cleaned"

## help: Show this help
help:
	@echo "Mirage CLI — Build targets"
	@grep -E '^## ' Makefile | sed 's/## /  /'
