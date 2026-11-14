# libretro-llvm: the part of LLVM that libretro cores link, built with make
# and a compiler - no CMake, nothing to install, nothing fetched.
#
#   make                    libllvm.a and the headers TableGen writes, for
#                           this machine
#   make platform=win       for Windows, with MinGW-w64 (CC, CXX, AR name
#                           the cross tools; TableGen is built with HOST_CXX)
#   make arch=aarch64       for ARM64
#   make LLVM_OUT=dir       objects and generated headers go to dir
#                           (default: build)
#   make V=1                show the commands
#
# A program that uses it compiles with
#   -Illvm/include -I$(LLVM_OUT)/gen/include
#   -Imake/include/<linux|windows|darwin> -Imake/include/<x86|aarch64>
#   -Imake/include/common
# and links $(LLVM_ARCHIVE). A core that carries a copy of this tree builds
# it from its own Makefile the same way: make/llvm.mk has the lists.

ifeq ($(V),1)
   Q :=
   SAY := @true
else
   Q := @
   SAY := @echo
endif

ifeq ($(platform),)
   platform = unix
   ifeq ($(shell uname -s),)
      platform = win
   else ifneq ($(findstring Darwin,$(shell uname -s)),)
      platform = osx
   else ifneq ($(findstring MINGW,$(shell uname -s)),)
      platform = win
   endif
endif

# The processor LLVM is built for
ifeq ($(arch),)
   ifneq (,$(findstring win,$(platform)))
      arch := $(shell $(CC) -dumpmachine 2>/dev/null | cut -d- -f1)
   else
      arch := $(shell uname -m)
   endif
endif
ifneq (,$(filter aarch64 arm64,$(arch)))
   IS_ARM64 := 1
endif

ifeq ($(platform),unix)
   fpic := -fPIC
else ifeq ($(platform),osx)
   fpic := -fPIC
else ifeq (,$(findstring win,$(platform)))
   $(error platform $(platform) is not one this Makefile builds for: unix, osx or win)
endif

ifeq ($(IS_ARM64),1)
   ARCH_FLAGS ?= $(if $(filter osx,$(platform)),-march=armv8.4-a,-march=armv8.1-a)
else
   ARCH_FLAGS ?= -msse -msse2 -mcx16
endif

HOST_CC  ?= cc
VISIBILITY ?= -fvisibility=hidden

LLVM_SRC := llvm

# The system and processor LLVM is built for, and those of the machine
# that runs the build, for TableGen
LLVM_OS   := $(if $(findstring win,$(platform)),windows,$(if $(filter osx,$(platform)),darwin,linux))
LLVM_ARCH := $(if $(filter 1,$(IS_ARM64)),aarch64,x86)
HOST_UNAME := $(shell uname -s 2>/dev/null)
HOST_OS   := $(if $(filter MINGW% MSYS% CYGWIN%,$(HOST_UNAME)),windows,$(if $(filter Darwin,$(HOST_UNAME)),darwin,linux))
HOST_ARCH := $(if $(filter aarch64 arm64,$(shell uname -m 2>/dev/null)),aarch64,x86)
HOST_EXE  := $(if $(filter windows,$(HOST_OS)),.exe)
HOST_CXX  ?= $(if $(filter $(LLVM_OS)-$(LLVM_ARCH),$(HOST_OS)-$(HOST_ARCH)),$(CXX),c++)

LLVM_OUT      ?= build
LLVM_GEN      := $(LLVM_OUT)/gen
LLVM_OBJ      := $(LLVM_OUT)/$(LLVM_OS)-$(LLVM_ARCH)
LLVM_HOST_OBJ := $(LLVM_OUT)/host-$(HOST_OS)-$(HOST_ARCH)
LLVM_MIN_TBLGEN := $(LLVM_HOST_OBJ)/llvm-min-tblgen$(HOST_EXE)
LLVM_TBLGEN     := $(LLVM_HOST_OBJ)/llvm-tblgen$(HOST_EXE)
LLVM_CFG        := make/include
LLVM_CONFIG_INC      = $(LLVM_CFG)/$(LLVM_OS) -I$(LLVM_CFG)/$(LLVM_ARCH) -I$(LLVM_CFG)/common
LLVM_HOST_CONFIG_INC = $(LLVM_CFG)/$(HOST_OS) -I$(LLVM_CFG)/$(HOST_ARCH) -I$(LLVM_CFG)/common

# Every TableGen input and TableGen's own sources: what its output is made
# again for (make/llvm.mk). Not the tool itself, which is linked again
# whenever one of the Support files it shares with LLVM changes.
LLVM_TD_DEPS := $(wildcard $(LLVM_SRC)/include/llvm/*/*.td $(LLVM_SRC)/include/llvm/*/*/*.td \
   $(LLVM_SRC)/lib/*/*.td $(LLVM_SRC)/lib/Target/*/*.td $(LLVM_SRC)/lib/Target/*/*/*.td \
   $(LLVM_SRC)/utils/TableGen/*.cpp $(LLVM_SRC)/utils/TableGen/*.h $(LLVM_SRC)/utils/TableGen/*/*.cpp $(LLVM_SRC)/utils/TableGen/*/*.h \
   $(LLVM_SRC)/lib/TableGen/*.cpp $(LLVM_SRC)/lib/TableGen/*.h $(LLVM_SRC)/include/llvm/TableGen/*.h)

llvm_objs = $(patsubst $(LLVM_SRC)/%,$(1)/%.o,$(2))
include make/llvm.mk

# What a core links: the common libraries, the target, and the perf
# listener on Linux
LLVM_SET  := $(if $(filter 1,$(IS_ARM64)),AARCH64,X86)
LLVM_SRCS := $(LLVM_LIB_COMMON_SRCS) $(LLVM_LIB_$(LLVM_SET)_SRCS) \
   $(if $(filter linux,$(LLVM_OS)),$(LLVM_LIB_PERFJITEVENTS_SRCS))
LLVM_OBJS := $(call llvm_objs,$(LLVM_OBJ),$(LLVM_SRCS))
LLVM_TBLGEN_OUT := $(LLVM_TBLGEN_COMMON) $(LLVM_TBLGEN_$(LLVM_SET))
LLVM_MIN_OBJS := $(call llvm_objs,$(LLVM_HOST_OBJ),$(LLVM_LLVM_MIN_TBLGEN_SRCS))
LLVM_TBLGEN_OBJS := $(call llvm_objs,$(LLVM_HOST_OBJ),$(LLVM_LLVM_TBLGEN_SRCS))
LLVM_ARCHIVE ?= $(LLVM_OUT)/libllvm.a

# As LLVM's release builds compile it
llvm_defs = $(if $(filter linux,$(1)),-D_GNU_SOURCE,$(if $(filter windows,$(1)),-D_FILE_OFFSET_BITS=64))
# LLVM's own files call libretro-common's retro_atomic where they had locks
# (libretro-common/include here; a core gives its own with LLVM_LRC_DIR):
# its headers after every other, so that none stands in for a system header
LLVM_LRC_DIR ?= libretro-common/include
LLVM_LRC_INC := -idirafter $(LLVM_LRC_DIR)
LLVM_CXXFLAGS := -std=c++17 -O2 -DNDEBUG -fno-exceptions -fno-rtti -funwind-tables \
   -fvisibility-inlines-hidden -ffunction-sections -fdata-sections -w -pthread $(fpic) $(VISIBILITY) $(ARCH_FLAGS) $(LLVM_LRC_INC)
LLVM_CFLAGS   := -O2 -DNDEBUG -ffunction-sections -fdata-sections -w $(fpic) $(VISIBILITY) $(ARCH_FLAGS)
LLVM_HOST_CXXFLAGS := -std=c++17 -O2 -DNDEBUG -fno-exceptions -fno-rtti -w -pthread $(LLVM_LRC_INC)
LLVM_HOST_LIBS := $(if $(filter windows,$(HOST_OS)),-lpsapi -lshell32 -lole32 -luuid -ladvapi32 -lws2_32 -lntdll,$(if $(filter darwin,$(HOST_OS)),,-lpthread -ldl -lm))

$(LLVM_MIN_OBJS) $(LLVM_TBLGEN_OBJS): LLVM_CONFIG_INC = $(LLVM_HOST_CONFIG_INC)
# llvm-tblgen's own sources include what llvm-min-tblgen writes
$(filter-out $(LLVM_MIN_OBJS),$(LLVM_TBLGEN_OBJS)): | $(LLVM_TBLGEN_TOOL)

.DEFAULT_GOAL := all

all: $(LLVM_ARCHIVE) $(LLVM_TBLGEN_OUT)

# Its objects through a list, too many for a command line on Windows
$(LLVM_ARCHIVE): $(LLVM_OBJS)
	$(SAY) AR $@
	$(Q)rm -f $@
	$(file >$@.list,$^)
	$(Q)$(AR) rcs $@ @$@.list
	$(Q)rm -f $@.list

$(LLVM_OBJ)/%.cpp.o: $(LLVM_SRC)/%.cpp | $(LLVM_TBLGEN_OUT)
	@mkdir -p $(@D)
	$(SAY) CXX $<
	$(Q)$(CXX) -MMD -MP -c -o $@ $< $(LLVM_CXXFLAGS) $(call llvm_defs,$(LLVM_OS)) $(LLVM_CPPFLAGS) $(CPPFLAGS)

$(LLVM_OBJ)/%.c.o: $(LLVM_SRC)/%.c | $(LLVM_TBLGEN_OUT)
	@mkdir -p $(@D)
	$(SAY) CC $<
	$(Q)$(CC) -MMD -MP -c -o $@ $< $(LLVM_CFLAGS) $(call llvm_defs,$(LLVM_OS)) $(LLVM_CPPFLAGS) $(CPPFLAGS)

# TableGen, for the machine that runs the build
$(LLVM_HOST_OBJ)/%.cpp.o: $(LLVM_SRC)/%.cpp
	@mkdir -p $(@D)
	$(SAY) HOSTCXX $<
	$(Q)$(HOST_CXX) -MMD -MP -c -o $@ $< $(LLVM_HOST_CXXFLAGS) $(call llvm_defs,$(HOST_OS)) $(LLVM_CPPFLAGS)

$(LLVM_HOST_OBJ)/%.c.o: $(LLVM_SRC)/%.c
	@mkdir -p $(@D)
	$(SAY) HOSTCC $<
	$(Q)$(HOST_CC) -MMD -MP -c -o $@ $< -O2 -DNDEBUG -w $(call llvm_defs,$(HOST_OS)) $(LLVM_CPPFLAGS)

$(LLVM_MIN_TBLGEN): $(LLVM_MIN_OBJS)
	$(SAY) LINK $@
	$(Q)$(HOST_CXX) -o $@ $^ -pthread $(LLVM_HOST_LIBS)

$(LLVM_TBLGEN): $(LLVM_TBLGEN_OBJS)
	$(SAY) LINK $@
	$(Q)$(HOST_CXX) -o $@ $^ -pthread $(LLVM_HOST_LIBS)

# What each of LLVM's objects includes, written as it is compiled: a header
# of LLVM's that is changed rebuilds what includes it. (LLVM's sources are
# the tree's own to change; without this only an object's own source did.)
-include $(LLVM_OBJS:.o=.d) $(LLVM_MIN_OBJS:.o=.d) $(LLVM_TBLGEN_OBJS:.o=.d)

clean:
	rm -rf $(LLVM_OUT)

.PHONY: all clean
