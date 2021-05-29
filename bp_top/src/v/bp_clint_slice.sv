
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_clint_slice
 import bp_common_pkg::*;
 import bp_be_pkg::*;
 import bsg_noc_pkg::*;
 import bsg_wormhole_router_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_bedrock_mem_if_widths(paddr_width_p, dword_width_gp, lce_id_width_p, lce_assoc_p, xce)
   )
  (input                                                clk_i
   , input                                              reset_i

   , input [xce_mem_msg_width_lp-1:0]                   mem_cmd_i
   , input                                              mem_cmd_v_i
   , output                                             mem_cmd_ready_and_o

   , output [xce_mem_msg_width_lp-1:0]                  mem_resp_o
   , output                                             mem_resp_v_o
   , input                                              mem_resp_yumi_i

   // Local interrupts
   , output                                             software_irq_o
   , output                                             timer_irq_o
   , output                                             external_irq_o
   );

  `declare_bp_bedrock_mem_if(paddr_width_p, dword_width_gp, lce_id_width_p, lce_assoc_p, xce);
  `declare_bp_memory_map(paddr_width_p, caddr_width_p);

  localparam debug_lp=0;

  bp_bedrock_xce_mem_msg_s mem_cmd_li, mem_cmd_lo;
  assign mem_cmd_li = mem_cmd_i;
  
  logic small_fifo_v_lo, small_fifo_yumi_li;
  bsg_one_fifo
   #(.width_p($bits(bp_bedrock_xce_mem_msg_s)))
   small_fifo
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
  
     ,.data_i(mem_cmd_li)
     ,.v_i(mem_cmd_v_i)
     ,.ready_o(mem_cmd_ready_and_o)
  
     ,.data_o(mem_cmd_lo)
     ,.v_o(small_fifo_v_lo)
     ,.yumi_i(small_fifo_yumi_li)
     );
  
  logic mipi_cmd_v;
  logic mtimecmp_cmd_v;
  logic mtime_cmd_v, mtime_cmd_hi_v;
  logic plic_cmd_v;
  logic wr_not_rd;
  
  bp_local_addr_s local_addr;
  assign local_addr = mem_cmd_lo.header.addr;
  
  always_comb
    begin
      mtime_cmd_v    = 1'b0;
      mtimecmp_cmd_v = 1'b0;
      mipi_cmd_v     = 1'b0;
      plic_cmd_v     = 1'b0;

      mtime_cmd_hi_v = 1'b0;

      wr_not_rd = mem_cmd_lo.header.msg_type inside {e_bedrock_mem_wr, e_bedrock_mem_uc_wr};

      unique
      casez ({local_addr.dev, local_addr.addr})
        mtime_reg_addr_gp        : mtime_cmd_v    = small_fifo_v_lo;
        mtime_reg_addr_gp+4      : mtime_cmd_hi_v = small_fifo_v_lo; // we support reading from the high word only of mtime
                                                                     // allows interfacing with 32-bit axi lite bus
                                                                     // if a 8-byte access is done, top bits are zero'd
        mtimecmp_reg_base_addr_gp: mtimecmp_cmd_v = small_fifo_v_lo;
        mipi_reg_base_addr_gp    : mipi_cmd_v     = small_fifo_v_lo;
        plic_reg_base_addr_gp    : plic_cmd_v     = small_fifo_v_lo;
        default:
          begin
             `BSG_HIDE_FROM_VERILATOR(assert final (reset_i !== '0 || !small_fifo_v_lo) else)
             if (small_fifo_v_lo)
               $warning("%m: access to illegal address %x\n",
                        {local_addr.dev, local_addr.addr});
          end
      endcase
    end

  logic [dword_width_gp-1:0] mtime_r, mtime_val_li, mtimecmp_n, mtimecmp_r;
  logic                     mipi_n, mipi_r;
  logic                     plic_n, plic_r;

  // TODO: Should be actual RTC
  localparam ds_width_lp = 5;
  localparam [ds_width_lp-1:0] ds_ratio_li = 8;
  logic mtime_inc_li;
  bsg_strobe
   #(.width_p(ds_width_lp))
   bsg_rtc_strobe
    (.clk_i(clk_i)
     ,.reset_r_i(reset_i)
     ,.init_val_r_i(ds_ratio_li)
     ,.strobe_r_o(mtime_inc_li)
     );
  assign mtime_val_li = mem_cmd_lo.data[0+:dword_width_gp];
  wire mtime_w_v_li = wr_not_rd & mtime_cmd_v;
  bsg_counter_set_en
   #(.max_val_p(0) // Unused but must be set to override default
     ,.lg_max_val_lp(dword_width_gp)
     ,.reset_val_p(0)
     )
   mtime_counter
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
  
     ,.set_i(mtime_w_v_li)
     ,.en_i(mtime_inc_li)
     ,.val_i(mtime_val_li)
     ,.count_o(mtime_r)
     );
  
  assign mtimecmp_n = mem_cmd_lo.data[0+:dword_width_gp];
  wire mtimecmp_w_v_li = wr_not_rd & mtimecmp_cmd_v;
  bsg_dff_reset_en
   #(.width_p(dword_width_gp))
   mtimecmp_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
  
     ,.en_i(mtimecmp_w_v_li)
     ,.data_i(mtimecmp_n)
     ,.data_o(mtimecmp_r)
     );
  assign timer_irq_o = (mtime_r >= mtimecmp_r);
  
  assign mipi_n = mem_cmd_lo.data[0];
  wire mipi_w_v_li = wr_not_rd & mipi_cmd_v;
  bsg_dff_reset_en
   #(.width_p(1))
   mipi_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.en_i(mipi_w_v_li)
  
     ,.data_i(mipi_n)
     ,.data_o(mipi_r)
     );
  assign software_irq_o = mipi_r;
  
  assign plic_n = mem_cmd_lo.data[0];
  wire plic_w_v_li = wr_not_rd & plic_cmd_v;
  bsg_dff_reset_en
   #(.width_p(1))
   plic_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.en_i(plic_w_v_li)
  
     ,.data_i(plic_n)
     ,.data_o(plic_r)
     );
  assign external_irq_o = plic_r;

  wire [dword_width_gp-1:0] rdata_lo;

   // handles case of invalid address correctly by returning zero
  bsg_mux_one_hot #(.width_p(dword_width_gp)
                    ,.els_p(5)
                    ,.harden_p(0)
                    ) rdmux
   (.data_i({    dword_width_gp ' (plic_r)
               , dword_width_gp ' (mipi_r)
               , dword_width_gp ' (mtimecmp_r)
               , dword_width_gp ' (mtime_r)
               , dword_width_gp ' (mtime_r >> 32)
             })
    ,.sel_one_hot_i( {plic_cmd_v, mipi_cmd_v, mtimecmp_cmd_v, mtime_cmd_v, mtime_cmd_hi_v })
    ,.data_o(rdata_lo)
    );

  bp_bedrock_xce_mem_msg_s mem_resp_lo;
  assign mem_resp_lo =
    '{header : '{
      msg_type       : mem_cmd_lo.header.msg_type
      ,subop         : e_bedrock_store
      ,addr          : mem_cmd_lo.header.addr
      ,payload       : mem_cmd_lo.header.payload
      ,size          : mem_cmd_lo.header.size
      }
      ,data          : dword_width_gp'(rdata_lo)
      };
  assign mem_resp_o = mem_resp_lo;
  assign mem_resp_v_o = small_fifo_v_lo;
  assign small_fifo_yumi_li = mem_resp_yumi_i;

 if (debug_lp)
   always @(negedge clk_i)
     begin
        if (~reset_i)
          if (mem_resp_v_o)
            $display("%m: write=%b response msg_type=%b addr=%h payload=%h size=%h data=%h"
                     ,wr_not_rd
                     ,mem_cmd_lo.header.msg_type
                     ,mem_cmd_lo.header.addr
                     ,mem_cmd_lo.header.payload
                     ,mem_cmd_lo.header.size
                     ,dword_width_gp' (rdata_lo)
                     );
     end

endmodule

