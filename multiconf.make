# ##########################################################################
# multiconf.make
# Copyright (C) Yann Collet
#
# GPL v2 License
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# ##########################################################################

# Provides build_library, build_program and build_cxx_program
# Provides V=1 / VERBOSE=1 support. V=2 is used for debugging purposes.
# Provides ALL_PROGRAMS: contain all binary names created with above functions
# Support recompilation of impacted units when an associated *.h is updated.

# Requires:
# - vpath set to find all source files
# - C_SRCS, CXX_SRCS and ASM_SRCS variables defined
# - directory `obj/` available to cache object files.
#   alternatively, set CACHE_ROOT to some different value.
# Optional:
# - HASH can be set to a different custom hash program.

# build_*_program: generates a recipe for a target that will be built in a cache directory.
# The cache directory is automatically derived from the list of flags and compilers.
# The macro function takes up to 4 argument:
# - The name of the target
# - The list of object files to build in the cache directory
# - An optional list of dependencies that will not be built in the cache directory
# - An optional complementary recipe code, that will run after compilation and link


# Silent mode is default; use V = 1 or VERBOSE = 1 to see compilation lines
VERBOSE ?= $(V)
$(VERBOSE).SILENT:

# Directory where object files will be built
CACHE_ROOT := obj

# Header Dependency management
DEPFLAGS = -MT $@ -MMD -MP -MF

# Automatic determination of build artifacts cache directory, keyed on build
# flags, so that we can do incremental, parallel builds of different binaries
# with different build flags without collisions.

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
  HASH ?= md5
else ifeq ($(UNAME), FreeBSD)
  HASH ?= gmd5sum
else ifeq ($(UNAME), OpenBSD)
  HASH ?= md5
endif
HASH ?= md5sum

HAVE_HASH := $(shell echo 1 | $(HASH) > /dev/null && echo 1 || echo 0)
ifeq ($(HAVE_HASH),0)
  $(info warning : could not find HASH ($(HASH)), required to differentiate builds using different flags)
  HASH_FUNC = generic/$(1)
else
  HASH_FUNC = $(firstword $(shell echo $(2) | $(HASH) ))
endif

# OSX linker doen't support --whole-archive and --no-whole-archive, so we are using -force_load and
# -load_hidden instead
ifeq ($(UNAME), Darwin)
	WHOLE_ARCHIVE = -force_load
	NO_WHOLE_ARCHIVE = -load_hidden
else
	WHOLE_ARCHIVE = --whole-archive
	NO_WHOLE_ARCHIVE = --no-whole-archive
endif


MKDIR ?= mkdir
RANLIB ?= ranlib
LN ?= ln
CURL ?= curl

# Create build directories on-demand.
#
# For some reason, make treats the directory as an intermediate file and tries
# to delete it. So we work around that by marking it "precious". Solution found
# here:
# http://ismail.badawi.io/blog/2017/03/28/automatic-directory-creation-in-make/
.PRECIOUS: $(CACHE_ROOT)/%/.
$(CACHE_ROOT)/%/. :
	$(MKDIR) -p $@

# Include dependency files
include $(wildcard $(CACHE_ROOT)/**/*.d)
include $(wildcard $(CACHE_ROOT)/generic/*/*.d)

define addTargetObject  # targetName, addlDeps
ifeq ($$(V),2)
$$(info $$(call addTargetObject,$(1)))
endif

.PRECIOUS: $$(CACHE_ROOT)/%/$(1)
$$(CACHE_ROOT)/%/$(1) : $(1:.o=.c) $(2) | $$(CACHE_ROOT)/%/.
	@echo CC $$@
	$$(CC) $$(CPPFLAGS) $$(CFLAGS) $$(DEPFLAGS) $$(CACHE_ROOT)/$$*/$(1:.o=.d) -c $$< -o $$@

endef # addTargetObject

define addTargetAsmObject  # targetName, addlDeps
ifeq ($$(V),2)
$$(info $$(call addTargetAsmObject,$(1)))
endif

.PRECIOUS: $$(CACHE_ROOT)/%/$(1)
$$(CACHE_ROOT)/%/$(1) : $(1:.o=.S) $(2) | $$(CACHE_ROOT)/%/.
	@echo AS $$@
	$$(CC) $$(CPPFLAGS) $$(CXXFLAGS) $$(DEPFLAGS) $$(CACHE_ROOT)/$$*/$(1:.o=.d) -c $$< -o $$@

endef # addTargetAsmObject

define addTargetCxxObject  # targetName, addlDeps
ifeq ($$(V),2)
$$(info $$(call addTargetCxxObject,$(1)))
endif

.PRECIOUS: $$(CACHE_ROOT)/%/$(1)
$$(CACHE_ROOT)/%/$(1) : $(1:.o=.cpp) $(2) | $$(CACHE_ROOT)/%/.
	@echo CXX $$@
	$$(CXX) $$(CPPFLAGS) $$(CXXFLAGS) $$(DEPFLAGS) $$(CACHE_ROOT)/$$*/$(1:.o=.d) -c $$< -o $$@

endef # addTargetCxxObject

define build_library  # targetName, targetDeps, addlDeps
ifeq ($$(V),2)
$$(info $$(call build_library,$(1),$(2),$(3)))
endif

# We first build a `.partial.a` file that is based on the lib's direct dependancies
# Those are also the dependencies that we will export
.PRECIOUS: $$(CACHE_ROOT)/%/$(1).partial.a
$$(CACHE_ROOT)/%/$(1).partial.a : $$(addprefix $$(CACHE_ROOT)/%/,$(2))
	@echo AR $$@
	$$(AR) $$(ARFLAGS) $$@ $$^
	$$(RANLIB) $$@

# After building the partial.a we turn it into a .o file
# by partially linking with the external dependencies
.PRECIOUS: $$(CACHE_ROOT)/%/$(1).o
$$(CACHE_ROOT)/%/$(1).o : $$(CACHE_ROOT)/%/$(1).partial.a  $(3)
	$$(CC) -r -nostdlib -o $$@ -Wl,$${WHOLE_ARCHIVE} $$< -Wl,$${NO_WHOLE_ARCHIVE} $$(wordlist 2,9999999,$$^)

# Finally we turn the .o file into a static lib.a file
.PRECIOUS: $$(CACHE_ROOT)/%/$(1)
$$(CACHE_ROOT)/%/$(1) : $$(CACHE_ROOT)/%/$(1).o
	@echo AR $$@
	$$(AR) $$(ARFLAGS) $$@ $$^
	$$(RANLIB) $$@

endef # build_library


SET_CACHE_DIRECTORY = \
   +$$(MAKE) --no-print-directory $$@ \
    CACHE_DIR=$$(CACHE_ROOT)/$$(call HASH_FUNC,$(1),$$(CC) $$(CXX) $$(CPPFLAGS) $$(CFLAGS) $$(CXXFLAGS) $$(LDFLAGS) $$(LDLIBS)) \
    CPPFLAGS="$$(CPPFLAGS)" \
    CFLAGS="$$(CFLAGS)" \
	CXXFLAGS="$$(CXXFLAGS)" \
    LDFLAGS="$$(LDFLAGS)" \
    LDLIBS="$$(LDLIBS)"

define build_c_program  # targetName, targetDeps, addlDeps, addlRecipe
ifeq ($$(V),2)
$$(info $$(call $(0),$(1),$(2),$(3)))
endif

ALL_PROGRAMS += $(1)

ifndef CACHE_DIR
.PHONY: $(1)  # must always be run
$(1):
	$(SET_CACHE_DIRECTORY)
else

$$(CACHE_ROOT)/%/$(1) : $$(addprefix $$(CACHE_ROOT)/%/,$(2)) $(3)
	@echo LINK $$@
	$$(CC) $$(CPPFLAGS) $$(CFLAGS) $$^ -o $$@ $$(LDFLAGS) $$(LDLIBS)
	$(4)

.PHONY: $(1)
$(1) : $$(CACHE_DIR)/$(1)
	$$(LN) -sf $$< $$@
endif # CACHE_DIR
endef # build_c_program


define build_cxx_program  # targetName, targetDeps, addlDeps
ifeq ($$(V),2)
$$(info $$(call $(0),$(1),$(2),$(3)))
endif

ALL_PROGRAMS += $(1)

ifndef CACHE_DIR
.PHONY: $(1)  # must always be run
$(1):
	$(SET_CACHE_DIRECTORY)
else

$$(CACHE_ROOT)/%/$(1) : $$(addprefix $$(CACHE_ROOT)/%/,$(2)) $(3)
	@echo LINK $$@
	$$(CXX) $$(CPPFLAGS) $$(CXXFLAGS) $$^ -o $$@ $$(LDFLAGS) $$(LDLIBS)

.PHONY: $(1)
$(1) : $$(CACHE_DIR)/$(1)
	$$(LN) -sf $$< $$@
endif # CACHE_DIR
endef # build_cxx_program


# Create targets for individual object files

C_OBJS  := $(patsubst %.c,%.o,$(C_SRCS))
CXXOBJS := $(patsubst %.cpp,%.o,$(CXX_SRCS))
ASMOBJS := $(patsubst %.S,%.o,$(ASM_SRCS))

$(foreach OBJ,$(C_OBJS),$(eval $(call addTargetObject,$(OBJ))))
$(foreach OBJ,$(ASMOBJS),$(eval $(call addTargetAsmObject,$(OBJ))))
$(foreach OBJ,$(CXXOBJS),$(eval $(call addTargetCxxObject,$(OBJ))))
