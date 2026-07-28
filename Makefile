# Roc platform template for Odin

# Detect native platform for `make` and `make native`.
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Linux)
  ifeq ($(UNAME_M),x86_64)
    NATIVE_TARGET := x64musl
  endif
  ifeq ($(UNAME_M),aarch64)
    NATIVE_TARGET := arm64musl
  endif
endif
ifeq ($(UNAME_S),Darwin)
  ifeq ($(UNAME_M),x86_64)
    NATIVE_TARGET := x64mac
  endif
  ifeq ($(UNAME_M),arm64)
    NATIVE_TARGET := arm64mac
  endif
endif

# Roc targets supported by the platform.
TARGETS := x64mac x64win x64musl arm64mac arm64win arm64musl

# Odin target names for each Roc target.
x64mac_TGT := darwin_amd64
x64win_TGT := windows_amd64
x64musl_TGT := linux_amd64
arm64mac_TGT := darwin_arm64
arm64win_TGT := windows_arm64
arm64musl_TGT := linux_arm64

# Library filename for each Roc target.
x64mac_LIB := libhost.a
x64win_LIB := host.lib
x64musl_LIB := libhost.a
arm64mac_LIB := libhost.a
arm64win_LIB := host.lib
arm64musl_LIB := libhost.a

# Source files.
SRC := src/host.odin src/roc_platform_abi.odin

# Library output paths for each target.
TARGET_LIBS := $(foreach t,$(TARGETS),platform/targets/$(t)/$($(t)_LIB))

# Native library output path.
NATIVE_LIB := platform/targets/$(NATIVE_TARGET)/$($(NATIVE_TARGET)_LIB)

.PHONY: native all clean test

# Default: build the native host library.
native: $(NATIVE_LIB)

all: $(TARGET_LIBS)

define TARGET_RULE
platform/targets/$(1)/$($(1)_LIB): $(SRC)
	odin build src -build-mode:static -target:$($(1)_TGT) -out:$$@
endef

$(foreach target,$(TARGETS),$(eval $(call TARGET_RULE,$(target))))

clean:
	rm -f platform/targets/*/libhost.a platform/targets/*/host.lib

test: native
	roc run examples/echo.roc <<< "hello"
