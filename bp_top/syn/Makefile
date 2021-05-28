## Set common environment variables
TOP ?= $(shell git rev-parse --show-toplevel)

include $(TOP)/Makefile.common

export SYN_PATH     := $(BP_TOP_DIR)/syn
export TB_PATH      := $(BP_TOP_DIR)/test/tb

export LOG_PATH     := $(BP_TOP_DIR)/syn/logs
export RESULTS_PATH := $(BP_TOP_DIR)/syn/results
export REPORT_PATH  := $(BP_TOP_DIR)/syn/reports
export TOUCH_PATH   := $(BP_TOP_DIR)/syn/touchfiles

export TB    ?= bp_tethered
export CFG   ?= e_bp_default_cfg
export DRAM  ?= dramsim3
export SUITE ?= bp-tests
export PROG  ?= hello_world
export TAG   ?= none

include $(TB_PATH)/$(TB)/Makefile.cfgs
include $(TB_PATH)/$(TB)/Makefile.params
include $(TB_PATH)/$(TB)/Makefile.testlist
include $(BP_COMMON_DIR)/syn/Makefile.common
include $(BP_COMMON_DIR)/syn/Makefile.dc
include $(BP_COMMON_DIR)/syn/Makefile.surelog
include $(BP_COMMON_DIR)/syn/Makefile.sv2v
include $(BP_COMMON_DIR)/syn/Makefile.verilator
include $(BP_COMMON_DIR)/syn/Makefile.vcs
include $(BP_COMMON_DIR)/syn/Makefile.vivado

