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

# Provides c_program(_shared_o) and cxx_program(_shared_o)
# Provides V=1 / VERBOSE=1 support. V=2 is used for debugging purposes.
# Provides target clean_cache: delete objects and binaries created with this script
# Support recompilation of only impacted units when an associated *.h is updated.

# Requires:
# - C_SRCDIRS, CXX_SRCDIRS, ASM_SRCDIRS defined
#   OR
#   C_SRCS, CXX_SRCS and ASM_SRCS variables defined
#   *and* vpath set to find all source files
#   OR
#   C_OBJS, CXX_OBJS and ASM_OBJS variables defined
#   *and* vpath set to find all source files
# - directory `cachedObjs/` available to cache object files.
#   alternatively, set CACHE_ROOT to some different value.
# Optional:
# - HASH can be set to a different custom hash program.

# *_program*: generates a recipe for a target that will be built in a cache directory.
# The cache directory is automatically derived from CACHE_ROOT and list of flags and compilers.
# *_shared_o* variant is an optional optimization variant, that make it possible for multiple targets to share the same objects.
# However, as a consequence, all these objects must have exactly the same list of flags,
# which in practice means that there must be no target-level modification (like: target: CFLAGS += someFlag).
# If unsure, only use the standars variants, c_program and cxx_program.

# All *_program* macro functions take up to 4 argument:
# - The name of the target
# - The list of object files to build in the cache directory
# - An optional list of dependencies for linking, that will not be built
# - An optional complementary recipe code, that will run after compilation and link


# Silent mode is default; use V = 1 or VERBOSE = 1 to see compilation lines
VERBOSE ?= $(V)
$(VERBOSE).SILENT:

# Directory where object files will be built
CACHE_ROOT := cachedObjs

# Dependency management
DEPFLAGS = -MT $@ -MMD -MP -MF

# Automatic determination of build artifacts cache directory, keyed on build
# flags, so that we can do incremental, parallel builds of different binaries
# with different build flags without collisions.

UNAME ?= $(shell uname)
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


define program_base  # targetName, targetDeps, addlDeps, addRecipe, hashSuffix, compiler, flags
ifeq ($$(V),2)
$$(info $$(call $(0),$(1),$(2),$(3),$(4),$(5),$(6),$(7)))
endif

ALL_PROGRAMS += $(1)
$$(CACHE_ROOT)/%/$(1) : $$(addprefix $$(CACHE_ROOT)/%/,$(2)) $(3)
	@echo LINK $$@
	$$($(6)) $$(CPPFLAGS) $$($(7)) $$^ -o $$@ $$(LDFLAGS) $$(LDLIBS)
	$(4)

.PHONY: $(1)
$(1) : $$(CACHE_ROOT)/$$(call HASH_FUNC,$(1),$$($(6)) $$(CPPFLAGS) $$($(7)) $$(LDFLAGS) $$(LDLIBS)$(5))/$(1)
	$$(LN) -sf $$< $$@$(EXT)
endef # program_base
# Note: $(EXT) must be set to .exe for Windows

define c_program  # targetName, targetDeps, addlDeps, addRecipe
$$(eval $$(call program_base,$(1),$(2),$(3),$(4),$(1),CC,CFLAGS))
endef # c_program

define c_program_shared_o  # targetName, targetDeps, addlDeps, addRecipe
$$(eval $$(call program_base,$(1),$(2),$(3),$(4),,CC,CFLAGS))
endef # c_program_shared_o

define cxx_program  # targetName, targetDeps, addlDeps, addRecipe
$$(eval $$(call program_base,$(1),$(2),$(3),$(4),$(1),CXX,CXXFLAGS))
endef # cxx_program

define cxx_program_shared_o  # targetName, targetDeps, addlDeps, addRecipe
$$(eval $$(call program_base,$(1),$(2),$(3),$(4),,CXX,CXXFLAGS))
endef # cxx_program_shared_o


# Create targets for individual object files

C_SRCS ?= $(notdir $(foreach dir,$(C_SRCDIRS),$(wildcard $(dir)/*.c)))
ifneq ($(strip $(C_SRCDIRS)),)
vpath %.c $(C_SRCDIRS)
endif
CXX_SRCS ?= $(notdir $(foreach dir,$(CXX_SRCDIRS),$(wildcard $(dir)/*.cpp)))
ifneq ($(strip $(CXX_SRCDIRS)),)
vpath %.cpp $(CXX_SRCDIRS)
endif
ASM_SRCS ?= $(notdir $(foreach dir,$(ASM_SRCDIRS),$(wildcard $(dir)/*.S)))
ifneq ($(strip $(ASM_SRCDIRS)),)
vpath %.S $(ASM_SRCDIRS)
endif

C_OBJS  ?= $(patsubst %.c,%.o,$(C_SRCS))
CXX_OBJS ?= $(patsubst %.cpp,%.o,$(CXX_SRCS))
ASM_OBJS ?= $(patsubst %.S,%.o,$(ASM_SRCS))

$(foreach OBJ,$(C_OBJS),$(eval $(call addTargetObject,$(OBJ))))
$(foreach OBJ,$(CXX_OBJS),$(eval $(call addTargetCxxObject,$(OBJ))))
$(foreach OBJ,$(ASM_OBJS),$(eval $(call addTargetAsmObject,$(OBJ))))


# Cleaning

clean_cache:
	$(RM) -rf $(CACHE_ROOT)
	$(RM) $(ALL_PROGRAMS)
