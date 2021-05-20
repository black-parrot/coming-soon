`ifndef BP_COMMON_DEFINES_SVH
`define BP_COMMON_DEFINES_SVH

  `include "bsg_defines.v"
  `include "bp_common_addr_defines.svh"
  `include "bp_common_aviary_defines.svh"
  `include "bp_common_bedrock_if.svh"
  `include "bp_common_cache_engine_if.svh"
  `include "bp_common_core_if.svh"
  `include "bp_common_cfg_bus_defines.svh"
  `include "bp_common_log_defines.svh"
  `include "bp_common_rv64_instr_defines.svh"
  `include "bp_common_rv64_csr_defines.svh"

  `include "bp_common_aviary_defines.svh"

  // floatControlWidth
  `include "HardFloat_consts.vi"

  // flControlDefault
  `include "HardFloat_specialize.vi"
`endif

