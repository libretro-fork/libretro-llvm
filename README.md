# libretro-llvm

The part of LLVM that libretro cores link for their recompilers, as plain
source built with `make` and a compiler: no CMake, nothing to install,
nothing fetched at build time.

It starts as LLVM 22.1.8 (llvm-project `ca7933e47d`), unchanged, trimmed to
what a JIT for x86-64 and ARM64 needs:

- `llvm/` - LLVM's sources: the libraries behind the `core`,
  `executionengine`, `mcjit` and `passes` components, the X86 and AArch64
  targets, the perf JIT listener, TableGen, the public headers and the
  TableGen inputs. No tests, tools, documentation, CMake or other targets.
- `third-party/siphash` - the one header LLVM takes from outside `llvm/`.
- `make/llvm.mk` - the sources of each library, what each is compiled with,
  and every TableGen run.
- `make/include/` - the headers LLVM's configuration would write: `config.h`
  and `llvm-config.h` for each system (`linux`, `windows`, `darwin`), the
  target lists for each processor (`x86`, `aarch64`), and the rest
  (`common`).
- `make/gen.py` - what wrote `llvm.mk` and `make/include/`, from LLVM's own
  build description. For moving to another LLVM release; it needs a full
  checkout of llvm-project, and is not part of a build.
- `Makefile` - builds `libllvm.a` and the headers TableGen writes.

## Building

    make
    make platform=win CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++ AR=x86_64-w64-mingw32-ar
    make arch=aarch64 CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ AR=aarch64-linux-gnu-ar

Linux, Windows (MinGW-w64) and macOS, x86-64 and ARM64. TableGen is built for
the machine that runs the build (`HOST_CXX`). The top of the `Makefile` says
what a program that uses the result compiles and links with.

## Cores

A core does not take this repository as a submodule: it carries a copy of
`llvm/`, `third-party/` and `make/` in its own tree and builds them from its
own Makefile, so a checkout of the core is everything its build needs.
parallel-ps3 has them as `3rdparty/llvm/llvm` and `rpcs3/libretro/make/llvm`.

This is not upstream LLVM and does not try to stay source-compatible with
it. It is changed for what the cores need - less code, fewer locks, fewer
copies - and what is not reached by a core is removed.

## Licence

LLVM's: Apache License 2.0 with LLVM exceptions, in `LICENSE.TXT`.
