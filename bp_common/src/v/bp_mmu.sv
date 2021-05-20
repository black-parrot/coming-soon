/*
 * bp_mmu.v
 */

`include "bp_common_defines.svh"

module bp_mmu
 import bp_common_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   , parameter `BSG_INV_PARAM(tlb_els_4k_p )
   , parameter `BSG_INV_PARAM(tlb_els_1g_p )

   , parameter entry_width_lp = `bp_pte_leaf_width(paddr_width_p)
   )
  (input                                              clk_i
   , input                                            reset_i

   , input                                            flush_i
   , input [1:0]                                      priv_mode_i
   , input                                            trans_en_i
   , input                                            sum_i
   , input                                            uncached_mode_i
   , input                                            nonspec_mode_i
   , input [hio_width_p-1:0]                       hio_mask_i

   , input                                            w_v_i
   , input [vtag_width_p-1:0]                         w_vtag_i
   , input [entry_width_lp-1:0]                       w_entry_i

   , input                                            r_v_i
   , input                                            r_instr_i
   , input                                            r_load_i
   , input                                            r_store_i
   , input [dword_width_gp-1:0]                       r_eaddr_i

   , output logic                                     r_v_o
   , output logic [ptag_width_p-1:0]                  r_ptag_o
   , output logic                                     r_miss_o
   , output logic                                     r_uncached_o
   , output logic                                     r_nonidem_o
   , output logic                                     r_instr_access_fault_o
   , output logic                                     r_load_access_fault_o
   , output logic                                     r_store_access_fault_o
   , output logic                                     r_instr_page_fault_o
   , output logic                                     r_load_page_fault_o
   , output logic                                     r_store_page_fault_o
   );

  `declare_bp_core_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);

  logic trans_en_r, r_v_r, r_instr_r, r_load_r, r_store_r, sum_r;
  logic [1:0] priv_mode_r;
  bsg_dff_reset
   #(.width_p(8))
   r_v_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i({sum_i, priv_mode_i, trans_en_i, r_v_i, r_instr_i, r_load_i, r_store_i})
     ,.data_o({sum_r, priv_mode_r, trans_en_r, r_v_r, r_instr_r, r_load_r, r_store_r})
     );

  logic [etag_width_p-1:0] r_etag_r;
  wire [etag_width_p-1:0] r_etag_li = r_eaddr_i[dword_width_gp-1-:etag_width_p];
  bsg_dff_reset
   #(.width_p(etag_width_p))
   etag_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i(r_etag_li)
     ,.data_o(r_etag_r)
     );

  logic tlb_bypass_r;
  wire tlb_bypass = ~w_v_i & (r_etag_li[0+:vtag_width_p] == r_etag_r[0+:vtag_width_p]) & r_v_r & trans_en_r & trans_en_i;
  bsg_dff_reset
   #(.width_p(1))
   tlb_bypass_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i(tlb_bypass)
     ,.data_o(tlb_bypass_r)
     );

  logic tlb_r_v_lo;
  bp_pte_leaf_s tlb_r_entry_lo;
  wire [vtag_width_p-1:0] w_vtag_li = w_v_i ? w_vtag_i : r_eaddr_i[vaddr_width_p-1-:vtag_width_p];
  bp_tlb
   #(.bp_params_p(bp_params_p), .els_4k_p(tlb_els_4k_p), .els_1g_p(tlb_els_1g_p))
   tlb
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.flush_i(flush_i)

     ,.v_i((r_v_i | w_v_i) & trans_en_i & ~tlb_bypass)
     ,.w_i(w_v_i)
     ,.vtag_i(w_vtag_li)
     ,.entry_i(w_entry_i)

     ,.v_o(tlb_r_v_lo)
     ,.entry_o(tlb_r_entry_lo)
     );

  bp_pte_leaf_s tlb_r_entry_r;
  logic tlb_r_v_r;
  bsg_dff_en_bypass
   #(.width_p(1+$bits(bp_pte_leaf_s)))
   entry_reg
    (.clk_i(clk_i)
     ,.en_i(~tlb_bypass_r)
     ,.data_i({tlb_r_v_lo, tlb_r_entry_lo})
     ,.data_o({tlb_r_v_r, tlb_r_entry_r})
     );

  bp_pte_leaf_s passthrough_entry, tlb_entry_lo;
  assign passthrough_entry = '{ptag: r_etag_r[0+:ptag_width_p], default: '0};
  assign tlb_entry_lo      = trans_en_r ? tlb_r_entry_r : passthrough_entry;
  wire tlb_v_lo            = trans_en_r ? tlb_r_v_r : r_v_r;

  wire ptag_v_lo                  = tlb_v_lo;
  wire [ptag_width_p-1:0] ptag_lo = tlb_entry_lo.ptag;
  logic ptag_uncached_lo, ptag_nonidem_lo;
  bp_pma
   #(.bp_params_p(bp_params_p))
   pma
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.ptag_v_i(ptag_v_lo)
     ,.ptag_i(ptag_lo)
     ,.uncached_mode_i(uncached_mode_i)
     ,.nonspec_mode_i(nonspec_mode_i)

     ,.uncached_o(ptag_uncached_lo)
     ,.nonidem_o(ptag_nonidem_lo)
     );

  // Fault if higher bits of eaddr do not match vaddr MSB
  wire eaddr_fault_v = ~&r_etag_r[etag_width_p-1:vtag_width_p-1] & |r_etag_r[etag_width_p-1:vtag_width_p-1];
  // Fault if hio bit is not enabled and we're accessing that hio
  wire hio_fault_v = (r_instr_r & ptag_lo[ptag_width_p-1-:hio_width_p] != '0)
    || (ptag_lo[ptag_width_p-1-:hio_width_p] & ~hio_mask_i);

  // Access faults
  wire instr_access_fault_v = r_instr_r & hio_fault_v;
  wire load_access_fault_v  = r_load_r  & hio_fault_v;
  wire store_access_fault_v = r_store_r & hio_fault_v;
  wire any_access_fault_v   = |{instr_access_fault_v, load_access_fault_v, store_access_fault_v};

  // Page faults
  wire instr_exe_page_fault_v  = ~tlb_entry_lo.x;
  wire instr_priv_page_fault_v = ((priv_mode_r == `PRIV_MODE_S) & tlb_entry_lo.u)
                                 | ((priv_mode_r == `PRIV_MODE_U) & ~tlb_entry_lo.u);
  wire data_priv_page_fault = ((priv_mode_r == `PRIV_MODE_S) & ~sum_r & tlb_entry_lo.u)
                                | ((priv_mode_r == `PRIV_MODE_U) & ~tlb_entry_lo.u);
  wire data_write_page_fault = r_store_r & (~tlb_entry_lo.w | ~tlb_entry_lo.d);
  wire instr_page_fault_v = trans_en_r & r_instr_r & (instr_priv_page_fault_v | instr_exe_page_fault_v);
  wire load_page_fault_v  = trans_en_r & r_load_r & (data_priv_page_fault | eaddr_fault_v);
  wire store_page_fault_v = trans_en_r & r_store_r & (data_priv_page_fault | data_write_page_fault | eaddr_fault_v);
  wire any_page_fault_v   = |{instr_page_fault_v, load_page_fault_v, store_page_fault_v};

  assign r_v_o                   = r_v_r &  tlb_v_lo & ~any_access_fault_v & ~any_page_fault_v;
  assign r_ptag_o                = ptag_lo;
  assign r_miss_o                = r_v_r & ~tlb_v_lo;
  assign r_uncached_o            = r_v_r & tlb_v_lo & ptag_uncached_lo;
  assign r_nonidem_o             = r_v_r & tlb_v_lo & ptag_nonidem_lo;
  assign r_instr_access_fault_o  = r_v_r & tlb_v_lo & instr_access_fault_v;
  assign r_load_access_fault_o   = r_v_r & tlb_v_lo & load_access_fault_v;
  assign r_store_access_fault_o  = r_v_r & tlb_v_lo & store_access_fault_v;
  assign r_instr_page_fault_o    = r_v_r & tlb_v_lo & instr_page_fault_v;
  assign r_load_page_fault_o     = r_v_r & tlb_v_lo & load_page_fault_v;
  assign r_store_page_fault_o    = r_v_r & tlb_v_lo & store_page_fault_v;

endmodule

<<<<<<< HEAD
`BSG_ABSTRACT_MODULE(bp_mmu)

=======

`BSG_ABSTRACT_MODULE(bp_mmu)
>>>>>>> reduce vivado load time from 18min to 2min, memory usage from 20GB to much less
