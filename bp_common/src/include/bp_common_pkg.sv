/*
 * bp_common_pkg.sv
 *
 * Contains the interface structures used for communicating between FE, BE, ME in BlackParrot.
 * Additionally contains global parameters used to configure the system. In the future, when
 *   multiple configurations are supported, these global parameters will belong to groups
 *   e.g. SV39, VM-disabled, ...
 *
 */

`include "bsg_defines.v"

package bp_common_pkg;

  /*
   * RV64 specifies a 64b effective address and 32b instruction.
   * BlackParrot supports SV39 virtual memory, which specifies 39b virtual / 56b physical address.
   * Effective addresses must have bits 39-63 match bit 38
   *   or a page fault exception will occur during translation.
   * Currently, we only support a very limited number of parameter configurations.
   * Thought: We could have a `define surrounding core instantiations of each parameter and then
   * when they import this package, `declare the if structs. No more casting!
   */

  localparam dword_width_gp       = 64;
  localparam word_width_gp        = 32;
  localparam half_width_gp        = 16;
  localparam byte_width_gp        = 8;
  localparam instr_width_gp       = 32;
  localparam csr_addr_width_gp    = 12;
  localparam reg_addr_width_gp    = 5;
  localparam page_offset_width_gp = 12;

  `include "bp_common_addr_pkgdef.svh"
  `include "bp_common_bedrock_pkgdef.svh"
  `include "bp_common_cache_pkgdef.svh"
  `include "bp_common_cache_engine_pkgdef.svh"
  `include "bp_common_cfg_bus_pkgdef.svh"
  `include "bp_common_clint_pkgdef.svh"
  `include "bp_common_core_pkgdef.svh"
  `include "bp_common_host_pkgdef.svh"
  `include "bp_common_rv64_pkgdef.svh"

  `include "bp_common_aviary_pkgdef.svh"

endpackage

