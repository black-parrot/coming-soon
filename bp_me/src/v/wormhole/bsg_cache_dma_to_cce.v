// 
// bsg_cache_dma_to_cce.v
// 
// Paul Gao   10/2019
//  
// 

`include "bp_me_cce_mem_if.vh"

module bsg_cache_dma_to_cce

  import bp_cce_pkg::*;
  import bp_common_pkg::*;
  import bp_common_aviary_pkg::*;
  import bp_me_pkg::*;
  
  import bsg_cache_pkg::*;
  
 #(// cache dma configuration
   parameter cache_addr_width_p                 = "inv"
  ,parameter data_width_p                       = "inv"
  ,parameter block_size_in_words_p              = "inv"

  ,parameter bp_params_e bp_params_p = e_bp_inv_cfg
  `declare_bp_proc_params(bp_params_p)
  `declare_bp_me_if_widths(paddr_width_p, cce_block_width_p, num_lce_p, lce_assoc_p)
  
  ,localparam bsg_cache_dma_pkt_width_lp        = `bsg_cache_dma_pkt_width(cache_addr_width_p)
  )
  
  (// Cache DMA side
   input                                                clk_i
  ,input                                                reset_i
  // Sending address and write_en               
  ,input        [bsg_cache_dma_pkt_width_lp-1:0]        dma_pkt_i
  ,input                                                dma_pkt_v_i
  ,output logic                                         dma_pkt_yumi_o
  // Sending cache block                        
  ,input        [data_width_p-1:0]                      dma_data_i
  ,input                                                dma_data_v_i
  ,output logic                                         dma_data_yumi_o
  // Receiving cache block                      
  ,output logic [data_width_p-1:0]                      dma_data_o
  ,output logic                                         dma_data_v_o
  ,input                                                dma_data_ready_i

  ,output [cce_mem_msg_width_lp-1:0]                    mem_cmd_o
  ,output                                               mem_cmd_v_o
  ,input                                                mem_cmd_yumi_i
                                                        
  ,input  [cce_mem_msg_width_lp-1:0]                    mem_resp_i
  ,input                                                mem_resp_v_i
  ,output                                               mem_resp_ready_o
  );
  
  localparam lg_fifo_depth_lp = 3;
  genvar i;
  
  /********************* Packet definition *********************/
  
  // Define cache DMA packet
  `declare_bsg_cache_dma_pkt_s(cache_addr_width_p);
  
  // cce
  `declare_bp_me_if(paddr_width_p, cce_block_width_p, num_lce_p, lce_assoc_p);
  
  
  /********************* dma packet fifo *********************/
  
  // This two-element fifo is necessary to avoid bubble between address flit
  // and data flit for cache evict operation
  
  logic dma_pkt_fifo_valid_lo, dma_pkt_fifo_yumi_li;
  bsg_cache_dma_pkt_s dma_pkt_fifo_data_lo;
  
  logic dma_pkt_fifo_ready_lo;
  assign dma_pkt_yumi_o = dma_pkt_v_i & dma_pkt_fifo_ready_lo;
  
  bsg_two_fifo
 #(.width_p(bsg_cache_dma_pkt_width_lp))
  dma_pkt_fifo
  (.clk_i  (clk_i  )
  ,.reset_i(reset_i)
  ,.ready_o(dma_pkt_fifo_ready_lo)
  ,.data_i (dma_pkt_i            )
  ,.v_i    (dma_pkt_v_i          )
  ,.v_o    (dma_pkt_fifo_valid_lo)
  ,.data_o (dma_pkt_fifo_data_lo )
  ,.yumi_i (dma_pkt_fifo_yumi_li )
  );
  
  
  /********************* cache DMA -> cce *********************/
  
  // send cache DMA packet
  bsg_cache_dma_pkt_s send_dma_pkt_n, send_dma_pkt_r;
  logic [data_width_p-1:0] data_n;
  logic [block_size_in_words_p-1:0][data_width_p-1:0] data_r ;
  
  logic mem_cmd_v_lo;
  bp_cce_mem_msg_s mem_cmd_lo;
  
  assign mem_cmd_lo.msg_type = (send_dma_pkt_r.write_not_read)? 
                                e_cce_mem_wb : e_cce_mem_rd;
  assign mem_cmd_lo.addr     = paddr_width_p'(send_dma_pkt_r.addr);
  assign mem_cmd_lo.payload  = '0;
  assign mem_cmd_lo.size     = e_mem_size_64;
  assign mem_cmd_lo.data     = (send_dma_pkt_r.write_not_read)? data_r : '0;
  
  assign mem_cmd_o           = mem_cmd_lo;
  assign mem_cmd_v_o         = mem_cmd_v_lo;

  logic [7:0] count_r, count_n;
  
  // State machine
  typedef enum logic [2:0] {
    RESET
   ,READY
   ,SEND_DATA
   ,SEND
  } dma_state_e;
  
  dma_state_e dma_state_r, dma_state_n;
  
  always_ff @(posedge clk_i)
    if (reset_i)
      begin
        dma_state_r <= RESET;
        count_r     <= '0;
        send_dma_pkt_r <= '0;
      end
    else
      begin
        dma_state_r <= dma_state_n;
        count_r     <= count_n;
        send_dma_pkt_r <= send_dma_pkt_n;
        data_r[count_r] <= data_n;
      end
  
  always_comb
  begin
    // internal control
    dma_state_n            = dma_state_r;
    count_n                = count_r;
    // send control
    dma_pkt_fifo_yumi_li   = 1'b0;
    dma_data_yumi_o        = 1'b0;
    mem_cmd_v_lo           = 1'b0;
    
    send_dma_pkt_n = send_dma_pkt_r;
    data_n = data_r[count_r];
    
    case (dma_state_r)
    RESET:
      begin
        dma_state_n = READY;
      end
    READY:
      begin
        if (dma_pkt_fifo_valid_lo)
          begin
            send_dma_pkt_n = dma_pkt_fifo_data_lo;
            dma_pkt_fifo_yumi_li = 1'b1;
            dma_state_n = (dma_pkt_fifo_data_lo.write_not_read)? SEND_DATA : SEND;
          end
      end
    SEND_DATA:
      begin
        if (dma_data_v_i)
          begin
            dma_data_yumi_o = 1'b1;
            data_n = dma_data_i;
            count_n = count_r + 1;
            if (count_r == block_size_in_words_p-1)
              begin
                count_n = 0;
                dma_state_n = SEND;
              end
          end
      end
    SEND:
      begin
        mem_cmd_v_lo = 1'b1;
        if (mem_cmd_yumi_i)
          begin
            dma_state_n = READY;
          end
      end
    default:
      begin
      end
    endcase
  end
  
  
  /********************* cce -> Cache DMA *********************/
  
  logic piso_v_li, piso_ready_lo, two_fifo_v_lo, two_fifo_yumi_li;
  bp_cce_mem_msg_s mem_resp_li;
  
  bsg_two_fifo
 #(.width_p(cce_mem_msg_width_lp)
  ) two_fifo
  (.clk_i(clk_i)
  ,.reset_i(reset_i)
  ,.v_i(mem_resp_v_i)
  ,.data_i(mem_resp_i)
  ,.ready_o(mem_resp_ready_o)
  ,.v_o(two_fifo_v_lo)
  ,.data_o(mem_resp_li)
  ,.yumi_i(two_fifo_yumi_li)
  );

  assign piso_v_li = two_fifo_v_lo & (mem_resp_li.msg_type == e_cce_mem_rd);
  assign two_fifo_yumi_li = two_fifo_v_lo & ((mem_resp_li.msg_type == e_cce_mem_wb) | piso_ready_lo);
  
  bsg_parallel_in_serial_out 
 #(.width_p(data_width_p)
  ,.els_p(block_size_in_words_p)
  ) piso
  (.clk_i(clk_i)
  ,.reset_i(reset_i)
  ,.valid_i(piso_v_li)
  ,.data_i(mem_resp_li.data)
  ,.ready_o(piso_ready_lo)
  ,.valid_o(dma_data_v_o)
  ,.data_o(dma_data_o)
  ,.yumi_i(dma_data_v_o & dma_data_ready_i)
  );
  
  
endmodule