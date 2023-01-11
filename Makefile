#!/usr/bin/make -f

ifeq ($(shell test -d .git || echo false),false)
  # Without .git/ we excpted the VERSION and COMMIT explicity provided.
  # (For example, when called from our Dockerfile)
  BUILD_VERSION ?= unknown
  BUILD_COMMIT ?= unknown
  VERSION := $(BUILD_VERSION)
  COMMIT := $(BUILD_COMMIT)
else
  # Otherwise, grab the VERSION and COMMIT from git
  VERSION := $(shell echo $(shell git describe --tags) | sed 's/^v//')
  COMMIT := $(shell git log -1 --format='%H')
endif

LEDGER_ENABLED ?= true
SDK_PACK := $(shell go list -m github.com/cosmos/cosmos-sdk | sed  's/ /\@/g')
GO_VERSION := $(shell cat go.mod | grep -E 'go [0-9].[0-9]+' | cut -d ' ' -f 2)
DOCKER := $(shell which docker)
BUILDDIR ?= $(CURDIR)/build

# Environment variable LAVA_BUILD_OPTIONS may embed compile options;
#   Misc options: static, nostrip, cleveldb, rocksdb
#   Lava options: mask_consumer_logs, debug_mutex

export GO111MODULE = on

# process build tags

build_tags = netgo
ifeq ($(LEDGER_ENABLED),true)
  ifeq ($(OS),Windows_NT)
    GCCEXE = $(shell where gcc.exe 2> NUL)
    ifeq ($(GCCEXE),)
      $(error gcc.exe not installed for ledger support, please install or set LEDGER_ENABLED=false)
    else
      build_tags += ledger
    endif
  else
    UNAME_S = $(shell uname -s)
    ifeq ($(UNAME_S),OpenBSD)
      $(warning OpenBSD detected, disabling ledger support (https://github.com/cosmos/cosmos-sdk/issues/1988))
    else
      GCC = $(shell command -v gcc 2> /dev/null)
      ifeq ($(GCC),)
        $(error gcc not installed for ledger support, please install or set LEDGER_ENABLED=false)
      else
        build_tags += ledger
      endif
    endif
  endif
endif

ifeq (cleveldb,$(findstring cleveldb,$(LAVA_BUILD_OPTIONS)))
  build_tags += gcc
else ifeq (rocksdb,$(findstring rocksdb,$(LAVA_BUILD_OPTIONS)))
  build_tags += gcc
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# process linker flags

ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=lava \
		  -X github.com/cosmos/cosmos-sdk/version.AppName=lavad \
		  -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
		  -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
		  -X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)"

ifeq (static,$(findstring static,$(LAVA_BUILD_OPTIONS)))
  # Due to Go shortcoming, using LINK_STATICALLY=true (with CGO_ENABLED unset)
  # builds a binary still dynamically linked.
  # Settings also CGO_ENABLED=1 successfully builds it statically linked, but
  # also spits annoying error: "loadinternal: cannot find runtime/cgo".
  # Setting only CGO_ENABLED=1 (without LINK_STATICALLY) successfully builds it
  # statically linked without complaints; So we do exactly that.
  export CGO_ENABLED = 0
  #LINK_STATICALLY := true
endif

ifeq (mask_consumer_logs,$(findstring mask_consumer_logs,$(LAVA_BUILD_OPTIONS)))
  ldflags += -X github.com/lavanet/lava/relayer/chainproxy.ReturnMaskedErrors=true
endif
ifeq (debug_mutex,$(findstring debug_mutex,$(LAVA_BUILD_OPTIONS)))
  ldflags += -X github.com/lavanet/lava/utils.TimeoutMutex=true
endif

ifeq (cleveldb,$(findstring cleveldb,$(LAVA_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
else ifeq (rocksdb,$(findstring rocksdb,$(LAVA_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=rocksdb
endif
ifeq (,$(findstring nostrip,$(LAVA_BUILD_OPTIONS)))
  ldflags += -w -s
endif
ifeq ($(LINK_STATICALLY),true)
	ldflags += -linkmode=external -extldflags "-Wl,-z,muldefs -static"
endif

ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'
# check for nostrip option
ifeq (,$(findstring nostrip,$(LAVA_BUILD_OPTIONS)))
  BUILD_FLAGS += -trimpath
endif

###############################################################################
###                                  Build                                  ###
###############################################################################

all: lint test

BUILD_TARGETS := build install

build: BUILD_ARGS=-o $(BUILDDIR)/

$(BUILD_TARGETS): go.sum $(BUILDDIR)/
	go $@ -mod=readonly $(BUILD_FLAGS) $(BUILD_ARGS) ./...

$(BUILDDIR)/:
	mkdir -p $(BUILDDIR)/

# Cross-building for arm64 from amd64 (or viceversa) takes
# a lot of time due to QEMU virtualization but it's the only way (afaik)
# to get a statically linked binary with CosmWasm

build-reproducible: build-reproducible-amd64 build-reproducible-arm64

RUNNER_IMAGE_DEBIAN := debian:11-slim

# Note: this target expects TARGETARCH to be defined
build-reproducible-helper: $(BUILDDIR)/
	$(DOCKER) buildx create --name lavabuilder || true
	$(DOCKER) buildx use lavabuilder
	$(DOCKER) buildx build \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg GIT_VERSION=$(VERSION) \
		--build-arg GIT_COMMIT=$(COMMIT) \
		--build-arg RUNNER_IMAGE=$(RUNNER_IMAGE_DEBIAN) \
		--platform linux/$(TARGETARCH) \
		-t lava:local-$(TARGETARCH) \
		--load \
		-f Dockerfile .

# Note: this target expects TARGETARCH to be defined
build-reproducible-copier: $(BUILDDIR)/
	$(DOCKER) rm -f lavabinary 2> /dev/null || true
	$(DOCKER) create -ti --name lavabinary lava:local-$(TARGETARCH)
	$(DOCKER) cp lavabinary:/bin/lavad $(BUILDDIR)/lavad-linux-$(TARGETARCH)
	$(DOCKER) rm -f lavabinary

build-reproducible-amd64: TARGETARCH=amd64
build-reproducible-amd64: build-reproducible-helper build-reproducible-copier

build-reproducible-arm64: TARGETARCH=arm64
build-reproducible-arm64: build-reproducible-helper build-reproducible-copier

build-linux: go.sum
	LEDGER_ENABLED=false GOOS=linux GOARCH=amd64 $(MAKE) build

go-mod-cache: go.sum
	@echo "--> Download go modules to local cache"
	@go mod download

go.sum: go.mod
	@echo "--> Ensure dependencies have not been modified"
	@go mod verify

draw-deps:
	@# requires brew install graphviz or apt-get install graphviz
	go get github.com/RobotsAndPencils/goviz
	@goviz -i ./cmd/lavad -d 2 | dot -Tpng -o dependency-graph.png

test:
	@echo "--> Running tests"
	@go test -v ./x/...

lint:
	@echo "--> Running linter"
	golangci-lint run --config .golangci.yml

###############################################################################
###                                Docker                                  ###
###############################################################################

docker-build: TARGETARCH=$(shell GOARCH= go env GOARCH)
docker-build: build-reproducible-helper


.PHONY: all build build-linux install lint test \
	go-mod-cache go.sum draw-deps \
	build-reproducible build-reproducible-helper build-reproducible-copier \
        build-reproducible-amd64 build-reproducible-arm64 \
	docker-build

