
`include "bp_common_defines.svh"

// See diagram here:
// https://docs.google.com/presentation/d/1Lzs5EM5lxArRA8suZOd7sWpTPywQMzN7OwANmOuS5_U/edit
// In general, the idea is to have a data store for 4k pages and a separate data store for 1g
//   pages. Then we mux high PPNs and metadata from both 4k + 1g storage, and mux low PPNs
//   only from 4k storage

module bp_tlb
 import bp_common_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   // used instead of {i,d}tlb_els_4k_p, tlb_els_1g_p parameter in above struct
   , parameter `BSG_INV_PARAM(els_1g_p )
   , parameter `BSG_INV_PARAM(els_4k_p )

   , parameter pte_width_p         = sv39_pte_width_gp
   , parameter page_table_depth_p  = sv39_levels_gp
   , parameter pte_size_in_bytes_p = sv39_pte_size_in_bytes_gp
   , parameter page_idx_width_p    = sv39_page_idx_width_gp

   , localparam entry_width_lp = `bp_pte_leaf_width(paddr_width_p)
   )
  (input                               clk_i
   , input                             reset_i
   , input                             flush_i

   // Single read-write port, but writes also "read" from the TLB
   , input                             v_i
   , input                             w_i
   , input [vtag_width_p-1:0]          vtag_i
   , input [entry_width_lp-1:0]        entry_i

   , output logic                      v_o
   , output logic [entry_width_lp-1:0] entry_o
   );

  `declare_bp_core_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);
  // Signals must be 1 width
  parameter els_1g_lp = `BSG_MAX(els_1g_p, 1);

  localparam r_entry_low_bits_lp  = (sv39_levels_gp-1)*sv39_page_idx_width_gp;
  localparam r_entry_high_bits_lp = $bits(bp_pte_leaf_s) - r_entry_low_bits_lp;

  bp_pte_leaf_s entry;
  assign entry = entry_i;

  wire r_v_li = v_i & ~w_i;
  wire w_v_li = v_i &  w_i;

  logic flush_4k_li, flush_1g_li;

  // We shift so that ppn bits are LSB
  bp_pte_leaf_s entry_shifted;
  localparam [`BSG_SAFE_CLOG2(entry_width_lp)-1:0] entry_shamt_lp = ptag_width_p;
  bsg_rotate_left
   #(.width_p($bits(bp_pte_leaf_s)))
   entry_shift
    (.data_i(entry)
     ,.rot_i(entry_shamt_lp)
     ,.o(entry_shifted)
     );

  logic [vtag_width_p-1:0] vtag_r;
  logic r_v_r;
  bsg_dff_reset
   #(.width_p(vtag_width_p+1))
   r_v_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i({vtag_i, r_v_li})
     ,.data_o({vtag_r, r_v_r})
     );
  wire [r_entry_low_bits_lp-1:0] passthrough_low_bits = vtag_r[0+:r_entry_low_bits_lp];

  logic [els_4k_p-1:0] tag_r_match_4k_lo;
  logic [els_4k_p-1:0] tag_empty_4k_lo;
  logic [els_4k_p-1:0] repl_way_4k_lo;
  wire [els_4k_p-1:0] tag_4k_w_v_li = ({els_4k_p{w_v_li & ~entry.gigapage}} & repl_way_4k_lo) | {els_4k_p{flush_4k_li}};
  bsg_cam_1r1w_tag_array
   #(.width_p(vtag_width_p), .els_p(els_4k_p))
   tag_array_4k
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.w_v_i(tag_4k_w_v_li)
     ,.w_set_not_clear_i(~flush_4k_li)
     ,.w_tag_i(vtag_i)
     ,.w_empty_o(tag_empty_4k_lo)

     ,.r_v_i(r_v_r)
     ,.r_tag_i(vtag_r)
     ,.r_match_o(tag_r_match_4k_lo)
     );
  wire any_match_4k_lo = |tag_r_match_4k_lo;

  bsg_cam_1r1w_replacement
   #(.els_p(els_4k_p))
   replacement_4k
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.read_v_i(tag_r_match_4k_lo)

     ,.alloc_v_i(w_v_li & ~entry.gigapage)
     ,.alloc_empty_i(tag_empty_4k_lo)
     ,.alloc_v_o(repl_way_4k_lo)
     );

  logic [els_1g_lp-1:0] tag_r_match_1g_lo;
  logic [els_1g_lp-1:0] tag_empty_1g_lo;
  logic [els_1g_lp-1:0] repl_way_1g_lo;
  wire [els_1g_lp-1:0] tag_1g_w_v_li = ({els_1g_lp{w_v_li & entry.gigapage}} & repl_way_1g_lo) | {els_1g_lp{flush_1g_li}};
  bsg_cam_1r1w_tag_array
   #(.width_p(vtag_width_p), .els_p(els_1g_p))
   tag_array_1g
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.w_v_i(tag_1g_w_v_li)
     ,.w_set_not_clear_i(~flush_1g_li)
     ,.w_tag_i(vtag_i)
     ,.w_empty_o(tag_empty_1g_lo)

     ,.r_v_i(r_v_r)
     ,.r_tag_i(vtag_r)
     ,.r_match_o(tag_r_match_1g_lo)
     );
  wire any_match_1g_lo = |tag_r_match_1g_lo;

  bsg_cam_1r1w_replacement
   #(.els_p(els_1g_p))
   replacement_1g
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.read_v_i(tag_r_match_1g_lo)

     ,.alloc_v_i(w_v_li & entry.gigapage)
     ,.alloc_empty_i(tag_empty_1g_lo)
     ,.alloc_v_o(repl_way_1g_lo)
     );

  logic [els_4k_p-1:0][r_entry_high_bits_lp-1:0] data_4k_high_r;
  logic [els_4k_p-1:0][r_entry_low_bits_lp-1:0] data_4k_low_r;
  wire [els_4k_p-1:0] mem_4k_w_v_li = ({els_4k_p{w_v_li & ~entry.gigapage}} & repl_way_4k_lo);
  for (genvar i = 0; i < els_4k_p; i++)
    begin : mem_array_4k
      bsg_dff_en
        #(.width_p(entry_width_lp))
        mem_reg
         (.clk_i(clk_i)
          ,.en_i(mem_4k_w_v_li[i])
          ,.data_i(entry_shifted)
          ,.data_o({data_4k_high_r[i], data_4k_low_r[i]})
          );
    end

  logic [els_1g_lp-1:0][r_entry_high_bits_lp-1:0] data_1g_high_r;
  wire [els_1g_lp-1:0] mem_1g_w_v_li = ({els_1g_lp{w_v_li & entry.gigapage}} & repl_way_1g_lo);
  for (genvar i = 0; i < els_1g_p; i++)
    begin : mem_array_1g
      bsg_dff_en
        #(.width_p(r_entry_high_bits_lp))
        mem_reg
         (.clk_i(clk_i)
          ,.en_i(mem_1g_w_v_li[i])
          ,.data_i(entry_shifted[r_entry_low_bits_lp+:r_entry_high_bits_lp])
          ,.data_o(data_1g_high_r[i])
          );
    end

  bp_pte_leaf_s r_entry;
  bsg_mux_one_hot
   #(.width_p(r_entry_low_bits_lp), .els_p(els_4k_p+1))
   one_hot_sel_low
    (.data_i({passthrough_low_bits, data_4k_low_r})
     ,.sel_one_hot_i({any_match_1g_lo, tag_r_match_4k_lo})
     ,.data_o(r_entry[0+:r_entry_low_bits_lp])
     );

  bsg_mux_one_hot
   #(.width_p(r_entry_high_bits_lp), .els_p(els_4k_p+els_1g_lp))
   one_hot_sel_high
    (.data_i({data_1g_high_r, data_4k_high_r})
     ,.sel_one_hot_i({tag_r_match_1g_lo, tag_r_match_4k_lo})
     ,.data_o(r_entry[r_entry_low_bits_lp+:r_entry_high_bits_lp])
     );

  wire r_v_lo = any_match_4k_lo ^ any_match_1g_lo;

  assign flush_4k_li = flush_i | (any_match_4k_lo & any_match_1g_lo);
  assign flush_1g_li = flush_i;

  // We shift so that ppn bits are LSB
  bp_pte_leaf_s entry_unshifted;
  bsg_rotate_right
   #(.width_p($bits(bp_pte_leaf_s)))
   entry_unshift
    (.data_i(r_entry)
     ,.rot_i(entry_shamt_lp)
     ,.o(entry_unshifted)
     );

  assign entry_o    = entry_unshifted;
  assign v_o        = r_v_r & r_v_lo;

endmodule

`BSG_ABSTRACT_MODULE(bp_tlb)

