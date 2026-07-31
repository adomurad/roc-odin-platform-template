[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# Roc platform template for Odin

A template for building [Roc platforms](https://www.roc-lang.org/platforms) using [Odin](https://odin-lang.org).

This is mostly based on https://github.com/lukewilliamboswell/roc-platform-template-zig.

I'm new to Odin and to platform development - not sure if this is correct, but with help of an LLM I was able to make it work.

I hope for official odin glue in the future and a tutorial how to start with platforms :)

## Requirements

- [Odin](https://odin-lang.org/docs/install/) (dev-2026 or later)
- [Roc](https://www.roc-lang.org/) (for bundling and running examples)

## Examples

The checked-in examples use the local `platform/main.roc`:

```roc
app [main!] { pf: platform "../platform/main.roc" }
```

Run examples with the interpreter:

```bash
roc examples/echo.roc
```

Build a standalone executable:

```bash
roc build examples/echo.roc
```

## Documentation

Generate docs locally:

```bash
roc docs platform/main.roc
```

## Testing

```bash
./build.sh test
```

This builds the native host library and then runs the `echo.roc` example.

## Building

```bash
# Build for all supported targets (cross-compilation)
./build.sh all

# Build for native platform only
./build.sh native
```

Cross-compilation requires the appropriate target toolchain support in your Odin/LLVM installation.

## Regenerating Glue

When the platform API changes (e.g. adding or modifying hosted functions in `platform/main.roc`), update the ABI declarations in `src/roc_platform_abi.odin` to match the new signatures and types. This project currently keeps the ABI bindings in Odin by hand; there is no Odin glue generator yet.

## Bundling

```bash
./bundle.sh
```

This creates a `.tar.zst` bundle containing all `.roc` files and prebuilt host libraries.

## Supported Targets

| Target | Library |
|--------|---------|
| x64mac | `platform/targets/x64mac/libhost.a` |
| x64win | `platform/targets/x64win/host.lib` |
| x64musl | `platform/targets/x64musl/libhost.a` |
| arm64mac | `platform/targets/arm64mac/libhost.a` |
| arm64musl | `platform/targets/arm64musl/libhost.a` |

Linux musl targets include statically linked C runtime files (`crt1.o`, `libc.a`) for standalone executables.
