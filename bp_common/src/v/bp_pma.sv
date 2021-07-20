
`include "bp_common_defines.svh"

module bp_pma
 import bp_common_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   )
  (input                          clk_i
   , input                        reset_i

   , input                        ptag_v_i
   , input [ptag_width_p-1:0]     ptag_i
   , input                        uncached_mode_i
   , input                        nonspec_mode_i

   , output logic                 uncached_o
   , output logic                 nonidem_o
   , output logic                 dram_o
   );

  wire is_local_addr = (ptag_i < (dram_base_addr_gp >> page_offset_width_gp));
  wire is_io_addr    = (ptag_i[ptag_width_p-1-:hio_width_p] != '0);

  assign uncached_o = ptag_v_i & (is_local_addr | is_io_addr | uncached_mode_i);
  // For now, uncached mode also means non-idempotency. Will reevaluate if we need
  //   a high-performance, unsafe, uncached mode
  assign nonidem_o  = ptag_v_i & (is_local_addr | is_io_addr | uncached_mode_i | nonspec_mode_i);
  assign dram_o     = ptag_v_i & (~is_local_addr | ~is_io_addr);

endmodule

