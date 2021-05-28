TOP ?= $(shell git rev-parse --show-toplevel)

.PHONY: help libs tools_lite tools tools_bsg tidy bleach_all

include $(TOP)/Makefile.common
include $(TOP)/Makefile.tools

help:
	@echo "usage: make [libs, tools, tools_lite, tools_bsg, tidy, bleach_all]"

libs: $(BP_TOOLS_LIB_DIR)/libdramsim3.so
$(BP_TOOLS_LIB_DIR)/libdramsim3.so:
	cd $(TOP); git submodule update --init --recursive --checkout $(BASEJUMP_STL_DIR)
	cd $(TOP); git submodule update --init --recursive --checkout $(HARDFLOAT_DIR)
	$(MAKE) -C $(BASEJUMP_STL_DIR)/bsg_test -f libdramsim3.mk
	mkdir -p $(BP_TOOLS_LIB_DIR)
	cp $(BASEJUMP_STL_DIR)/bsg_test/libdramsim3.so $(BP_TOOLS_LIB_DIR)/libdramsim3.so

TOOL_TARGET_DIRS := $(BP_TOOLS_BIN_DIR) $(BP_TOOLS_LIB_DIR) $(BP_TOOLS_INCLUDE_DIR) $(BP_TOOLS_TOUCH_DIR)
$(TOOL_TARGET_DIRS):
	mkdir -p $@

tools_lite: libs | $(TOOL_TARGET_DIRS)
	$(MAKE) verilator
	$(MAKE) dromajo

## This target makes the tools needed for the BlackParrot RTL
tools: tools_lite
	$(MAKE) bsg_sv2v
	$(MAKE) surelog

tools_bsg: tools bsg_cadenv

bsg_cadenv: $(BP_EXTERNAL_DIR)/bsg_cadenv
$(BP_EXTERNAL_DIR)/bsg_cadenv:
	-git clone git@github.com:bespoke-silicon-group/bsg_cadenv.git $(BP_EXTERNAL_DIR)/bsg_cadenv

tidy:
	echo "BlackParrot RTL is tidy enough"

## This target just wipes the whole repo clean.
#  Use with caution.
bleach_all:
	cd $(TOP); git clean -fdx; git submodule deinit -f .

