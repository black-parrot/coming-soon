/**
 *
 * Name:
 *   bp_be_pipe_mem.v
 *
 * Description:
 *   Pipeline for RISC-V memory instructions. This includes both int + float loads + stores.
 *
 * Notes:
 *
 */

`include "bp_common_defines.svh"
`include "bp_be_defines.svh"

module bp_be_pipe_mem
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_cache_engine_if_widths(paddr_width_p, ctag_width_p, dcache_sets_p, dcache_assoc_p, dword_width_gp, dcache_block_width_p, dcache_fill_width_p, dcache)
   // Generated parameters
   , localparam cfg_bus_width_lp       = `bp_cfg_bus_width(hio_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p)
   , localparam dispatch_pkt_width_lp  = `bp_be_dispatch_pkt_width(vaddr_width_p)
   , localparam ptw_fill_pkt_width_lp  = `bp_be_ptw_fill_pkt_width(vaddr_width_p, paddr_width_p)
   , localparam trans_info_width_lp    = `bp_be_trans_info_width(ptag_width_p)
   , localparam commit_pkt_width_lp    = `bp_be_commit_pkt_width(vaddr_width_p, paddr_width_p)
   )
  (input                                  clk_i
   , input                                reset_i

   , input [cfg_bus_width_lp-1:0]         cfg_bus_i
   , input                                flush_i
   , input                                sfence_i

   , output logic                         ready_o

   , input [dispatch_pkt_width_lp-1:0]    reservation_i

   , input [commit_pkt_width_lp-1:0]      commit_pkt_i
   , output [ptw_fill_pkt_width_lp-1:0]   ptw_fill_pkt_o
   , output logic                         ptw_busy_o

   , output logic                         tlb_load_miss_v_o
   , output logic                         tlb_store_miss_v_o
   , output logic                         cache_miss_v_o
   , output logic                         fencei_clean_v_o
   , output logic                         fencei_dirty_v_o
   , output logic                         load_misaligned_v_o
   , output logic                         load_access_fault_v_o
   , output logic                         load_page_fault_v_o
   , output logic                         store_misaligned_v_o
   , output logic                         store_access_fault_v_o
   , output logic                         store_page_fault_v_o

   , output logic [dpath_width_gp-1:0]    early_data_o
   , output logic                         early_v_o
   , output logic [dpath_width_gp-1:0]    final_data_o
   , output logic                         final_v_o

   , input [trans_info_width_lp-1:0]      trans_info_i
   , output logic                         replay_pending_o

   // D$-LCE Interface
   // signals to LCE
   , output logic [dcache_req_width_lp-1:0]          cache_req_o
   , output logic                                    cache_req_v_o
   , input                                           cache_req_yumi_i
   , input                                           cache_req_busy_i
   , output logic [dcache_req_metadata_width_lp-1:0] cache_req_metadata_o
   , output logic                                    cache_req_metadata_v_o
   , input                                           cache_req_critical_tag_i
   , input                                           cache_req_critical_data_i
   , input                                           cache_req_complete_i
   , input                                           cache_req_credits_full_i
   , input                                           cache_req_credits_empty_i

   , input                                           data_mem_pkt_v_i
   , input [dcache_data_mem_pkt_width_lp-1:0]        data_mem_pkt_i
   , output logic                                    data_mem_pkt_yumi_o
   , output logic [dcache_block_width_p-1:0]         data_mem_o

   , input                                           tag_mem_pkt_v_i
   , input [dcache_tag_mem_pkt_width_lp-1:0]         tag_mem_pkt_i
   , output logic                                    tag_mem_pkt_yumi_o
   , output logic [dcache_tag_info_width_lp-1:0]     tag_mem_o

   , input                                           stat_mem_pkt_v_i
   , input [dcache_stat_mem_pkt_width_lp-1:0]        stat_mem_pkt_i
   , output logic                                    stat_mem_pkt_yumi_o
   , output logic [dcache_stat_info_width_lp-1:0]    stat_mem_o
   );

  `declare_bp_core_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);
  `declare_bp_be_internal_if_structs(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);

  `declare_bp_cfg_bus_s(hio_width_p, core_id_width_p, cce_id_width_p, lce_id_width_p);
  `declare_bp_cache_engine_if(paddr_width_p, ptag_width_p, dcache_sets_p, dcache_assoc_p, dword_width_gp, dcache_block_width_p, dcache_fill_width_p, dcache);

  // Cast input and output ports
  bp_be_dispatch_pkt_s   reservation;
  bp_be_decode_s         decode;
  rv64_instr_s           instr;
  bp_cfg_bus_s           cfg_bus;
  bp_be_commit_pkt_s     commit_pkt;
  bp_be_ptw_fill_pkt_s   ptw_fill_pkt;
  bp_be_trans_info_s     trans_info;
  bp_dcache_req_s        cache_req_cast_o;

  assign cfg_bus = cfg_bus_i;
  assign ptw_fill_pkt_o = ptw_fill_pkt;
  assign commit_pkt = commit_pkt_i;
  assign trans_info = trans_info_i;
  assign cache_req_o = cache_req_cast_o;

  assign reservation = reservation_i;
  assign decode = reservation.decode;
  assign instr = reservation.instr;
  wire [vaddr_width_p-1:0] pc  = reservation.pc[0+:vaddr_width_p];
  wire [dpath_width_gp-1:0] rs1 = reservation.rs1[0+:dpath_width_gp];
  wire [dpath_width_gp-1:0] rs2 = reservation.rs2[0+:dpath_width_gp];
  wire [dpath_width_gp-1:0] imm = reservation.imm[0+:dpath_width_gp];

  /* Internal connections */
  /* TLB ports */
  logic                    dtlb_miss_v, dtlb_w_v, dtlb_r_v, dtlb_v_lo;
  logic [vtag_width_p-1:0] dtlb_w_vtag;
  bp_pte_leaf_s            dtlb_w_entry;

  /* PTW ports */
  logic [ptag_width_p-1:0]  ptw_dcache_ptag;
  logic                     ptw_dcache_ptag_v;
  logic                     ptw_dcache_v, ptw_busy;
  bp_be_dcache_pkt_s        ptw_dcache_pkt;

  /* D-Cache ports */
  bp_be_dcache_pkt_s        dcache_pkt;
  logic [dpath_width_gp-1:0] dcache_early_data, dcache_final_data;
  logic [ptag_width_p-1:0]  dcache_ptag;
  logic                     dcache_early_v, dcache_final_v, dcache_pkt_v;
  logic                     dcache_ptag_v;
  logic                     dcache_ptag_uncached;
  logic                     dcache_ptag_dram;
  logic                     dcache_ready_lo;

  logic load_access_fault_v, store_access_fault_v;
  logic load_page_fault_v, store_page_fault_v;
  logic load_misaligned_v, store_misaligned_v;

  /* Control signals */
  logic is_req_mem1, is_req_mem2;
  logic is_fencei_mem1, is_fencei_mem2;
  logic is_store_mem1, is_store_mem2;

  wire is_store  = (decode.pipe_mem_early_v | decode.pipe_mem_final_v) & decode.dcache_w_v;
  wire is_load   = (decode.pipe_mem_early_v | decode.pipe_mem_final_v) & decode.dcache_r_v;
  wire is_fencei = (decode.pipe_mem_early_v | decode.pipe_mem_final_v) & decode.fu_op inside {e_dcache_op_fencei};
  wire is_req    = reservation.v & (is_store | is_load);

  // Calculate cache access eaddr
  wire [rv64_eaddr_width_gp-1:0] eaddr = rs1 + imm;

  // D-TLB connections
  assign dtlb_r_v        = reservation.v & (decode.pipe_mem_early_v | decode.pipe_mem_final_v) & ~is_fencei;
  assign dtlb_w_v        = commit_pkt.dtlb_fill_v;
  assign dtlb_w_vtag     = commit_pkt.vaddr[vaddr_width_p-1-:vtag_width_p];
  assign dtlb_w_entry    = commit_pkt.pte_leaf;

  logic [ptag_width_p-1:0] dtlb_ptag_lo;
  bp_mmu
   #(.bp_params_p(bp_params_p)
     ,.tlb_els_4k_p(dtlb_els_4k_p)
     ,.tlb_els_1g_p(dtlb_els_1g_p)
     )
   dmmu
    (.clk_i(~clk_i)
     ,.reset_i(reset_i)

     ,.flush_i(sfence_i)
     ,.priv_mode_i(trans_info.priv_mode)
     ,.sum_i(trans_info.mstatus_sum)
     ,.trans_en_i(trans_info.translation_en)
     ,.uncached_mode_i((cfg_bus.dcache_mode == e_lce_mode_uncached))
     ,.nonspec_mode_i((cfg_bus.dcache_mode == e_lce_mode_nonspec))
     ,.hio_mask_i(cfg_bus.hio_mask)

     ,.w_v_i(dtlb_w_v)
     ,.w_vtag_i(dtlb_w_vtag)
     ,.w_entry_i(dtlb_w_entry)

     ,.r_v_i(dtlb_r_v)
     ,.r_instr_i('0)
     ,.r_load_i(is_load)
     ,.r_store_i(is_store)
     ,.r_eaddr_i(eaddr)

     ,.r_v_o(dtlb_v_lo)
     ,.r_ptag_o(dtlb_ptag_lo)
     ,.r_miss_o(dtlb_miss_v)
     ,.r_uncached_o(dcache_ptag_uncached)
     ,.r_nonidem_o(/* All D$ misses are non-speculative */)
     ,.r_dram_o(dcache_ptag_dram)
     ,.r_instr_access_fault_o()
     ,.r_load_access_fault_o(load_access_fault_v)
     ,.r_store_access_fault_o(store_access_fault_v)
     ,.r_instr_page_fault_o()
     ,.r_load_page_fault_o(load_page_fault_v)
     ,.r_store_page_fault_o(store_page_fault_v)
     );

  bp_be_ptw_miss_pkt_s ptw_miss_pkt;
  assign ptw_miss_pkt =
    '{instr_miss_v  : commit_pkt.itlb_miss
      ,store_miss_v : commit_pkt.dtlb_store_miss
      ,load_miss_v  : commit_pkt.dtlb_load_miss
      ,vaddr        : commit_pkt.itlb_miss ? commit_pkt.pc : commit_pkt.vaddr
      };

  bp_be_ptw
   #(.bp_params_p(bp_params_p))
    ptw
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.base_ppn_i(trans_info.satp_ppn)
     ,.priv_mode_i(trans_info.priv_mode)
     ,.mstatus_sum_i(trans_info.mstatus_sum)
     ,.mstatus_mxr_i(trans_info.mstatus_mxr)
     ,.busy_o(ptw_busy)

     ,.ptw_miss_pkt_i(ptw_miss_pkt)
     ,.ptw_fill_pkt_o(ptw_fill_pkt)

     ,.dcache_v_i(dcache_early_v)
     ,.dcache_data_i(dcache_early_data)

     ,.dcache_v_o(ptw_dcache_v)
     ,.dcache_pkt_o(ptw_dcache_pkt)
     ,.dcache_ptag_o(ptw_dcache_ptag)
     ,.dcache_ptag_v_o(ptw_dcache_ptag_v)
     ,.dcache_ready_i(dcache_ready_lo)
    );

  bp_be_dcache
    #(.bp_params_p(bp_params_p))
    dcache
     (.clk_i(clk_i)
      ,.reset_i(reset_i)

      ,.cfg_bus_i(cfg_bus_i)

      ,.dcache_pkt_i(dcache_pkt)
      ,.v_i(dcache_pkt_v)
      ,.ready_o(dcache_ready_lo)

      ,.ptag_i(dcache_ptag)
      ,.ptag_v_i(dcache_ptag_v)
      ,.ptag_uncached_i(dcache_ptag_uncached)
      ,.ptag_dram_i(dcache_ptag_dram)

      ,.early_v_o(dcache_early_v)
      ,.early_data_o(dcache_early_data)
      ,.final_data_o(dcache_final_data)
      ,.final_v_o(dcache_final_v)

      ,.flush_i(flush_i)
      ,.replay_pending_o(replay_pending_o)

      // D$-LCE Interface
      ,.cache_req_o(cache_req_cast_o)
      ,.cache_req_v_o(cache_req_v_o)
      ,.cache_req_yumi_i(cache_req_yumi_i)
      ,.cache_req_busy_i(cache_req_busy_i)
      ,.cache_req_metadata_o(cache_req_metadata_o)
      ,.cache_req_metadata_v_o(cache_req_metadata_v_o)
      ,.cache_req_critical_tag_i(cache_req_critical_tag_i)
      ,.cache_req_critical_data_i(cache_req_critical_data_i)
      ,.cache_req_complete_i(cache_req_complete_i)
      ,.cache_req_credits_full_i(cache_req_credits_full_i)
      ,.cache_req_credits_empty_i(cache_req_credits_empty_i)

      ,.data_mem_pkt_v_i(data_mem_pkt_v_i)
      ,.data_mem_pkt_i(data_mem_pkt_i)
      ,.data_mem_o(data_mem_o)
      ,.data_mem_pkt_yumi_o(data_mem_pkt_yumi_o)
      ,.tag_mem_pkt_v_i(tag_mem_pkt_v_i)
      ,.tag_mem_pkt_i(tag_mem_pkt_i)
      ,.tag_mem_o(tag_mem_o)
      ,.tag_mem_pkt_yumi_o(tag_mem_pkt_yumi_o)
      ,.stat_mem_pkt_v_i(stat_mem_pkt_v_i)
      ,.stat_mem_pkt_i(stat_mem_pkt_i)
      ,.stat_mem_o(stat_mem_o)
      ,.stat_mem_pkt_yumi_o(stat_mem_pkt_yumi_o)
      );

  // We delay the tlb miss signal by one cycle to synchronize with cache miss signal
  // We latch the dcache miss signal
  always_ff @(negedge clk_i)
    begin
      is_req_mem1 <= is_req;
      is_req_mem2 <= is_req_mem1;
      is_store_mem1 <= is_store;
      is_store_mem2 <= is_store_mem1;
      is_fencei_mem1 <= is_fencei;
      is_fencei_mem2 <= is_fencei_mem1;
    end

  // Check instruction accesses
  assign load_misaligned_v = 1'b0; // TODO: detect
  assign store_misaligned_v = 1'b0; // TODO: detect

  // D-Cache connections
  always_comb
    begin
      if(ptw_busy) begin
        dcache_pkt_v    = ptw_dcache_v;
        dcache_pkt      = ptw_dcache_pkt;
        dcache_ptag     = ptw_dcache_ptag;
        dcache_ptag_v   = ptw_dcache_ptag_v;
      end
      else begin
        // On flush_i, we flush the cache including including incoming requests
        dcache_pkt_v = reservation.v & (decode.pipe_mem_early_v | decode.pipe_mem_final_v);
        dcache_pkt.rd_addr     = instr.t.rtype.rd_addr;
        dcache_pkt.opcode      = bp_be_dcache_fu_op_e'(decode.fu_op);
        dcache_pkt.page_offset = eaddr[0+:page_offset_width_gp];
        dcache_pkt.data        = rs2;
        dcache_ptag = dtlb_ptag_lo;
        dcache_ptag_v = dtlb_v_lo;
      end
  end

  assign tlb_store_miss_v_o     = is_store_mem1 & dtlb_miss_v;
  assign tlb_load_miss_v_o      = ~is_store_mem1 & dtlb_miss_v;
  assign cache_miss_v_o         = is_req_mem2 & ~dcache_early_v;
  assign fencei_clean_v_o       = is_fencei_mem2 & dcache_early_v;
  assign fencei_dirty_v_o       = is_fencei_mem2 & ~dcache_early_v;
  assign store_page_fault_v_o   = store_page_fault_v;
  assign load_page_fault_v_o    = load_page_fault_v;
  assign store_access_fault_v_o = store_access_fault_v;
  assign load_access_fault_v_o  = load_access_fault_v;
  assign store_misaligned_v_o   = store_misaligned_v;
  assign load_misaligned_v_o    = load_misaligned_v;

  assign ready_o                = dcache_ready_lo;
  assign ptw_busy_o             = ptw_busy;
  assign early_data_o           = dcache_early_data;
  assign final_data_o           = dcache_final_data;

  wire early_v_li = reservation.v & reservation.decode.pipe_mem_early_v;
  bsg_dff_chain
   #(.width_p(1), .num_stages_p(1))
   early_chain
    (.clk_i(clk_i)

     ,.data_i(early_v_li)
     ,.data_o(early_v_o)
     );

  wire final_v_li = reservation.v & reservation.decode.pipe_mem_final_v;
  bsg_dff_chain
   #(.width_p(1), .num_stages_p(2))
   final_chain
    (.clk_i(clk_i)

     ,.data_i(final_v_li)
     ,.data_o(final_v_o)
     );

endmodule

