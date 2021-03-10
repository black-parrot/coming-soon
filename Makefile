TOP ?= $(shell git rev-parse --show-toplevel)

.PHONY: bleach_all libs tools sdk hdk prep prep_bsg

include $(TOP)/Makefile.common

libs:
	cd $(TOP); git submodule update --init --recursive --checkout $(BASEJUMP_STL_DIR)
	cd $(TOP); git submodule update --init --recursive --checkout $(HARDFLOAT_DIR)

tools: libs
	cd $(TOP); git submodule update --init --checkout $(BP_TOOLS_DIR)
	$(MAKE) -C $(BP_TOOLS_DIR) tools

sdk: tools
	cd $(TOP); git submodule update --init --checkout $(BP_SDK_DIR)
	$(MAKE) -C $(BP_SDK_DIR) sdk

hdk: sdk
	cd $(TOP); git submodule update --init --checkout $(BP_HDK_DIR)
	$(MAKE) -C $(BP_HDK_DIR) hdk

prep: hdk

prep_bsg: prep
	$(MAKE) bsg_cadenv
	$(MAKE) -C $(BP_TOOLS_DIR) bsg_cadenv
	$(MAKE) -C $(BP_SDK_DIR) bsg_cadenv
	$(MAKE) -C $(BP_HDK_DIR) bsg_cadenv

bsg_cadenv:
	cd $(BP_SDK_DIR); git clone git@github.com:bespoke-silicon-group/bsg_cadenv.git bsg_cadenv

tidy:
	$(MAKE) -C $(BP_TOOLS_DIR) tidy
	$(MAKE) -C $(BP_SDK_DIR) tidy
	$(MAKE) -C $(BP_HDK_DIR) tidy

## This target just wipes the whole repo clean.
#  Use with caution.
bleach_all:
	cd $(TOP); git clean -fdx; git submodule deinit -f .

