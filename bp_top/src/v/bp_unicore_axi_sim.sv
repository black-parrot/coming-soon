
`include "bp_common_defines.svh"
`include "bp_me_defines.svh"

module bp_unicore_axi_sim
 import bp_common_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)

   // AXI4-LITE PARAMS
   , parameter axi_lite_addr_width_p   = 32
   , parameter axi_lite_data_width_p   = 32
   
   , localparam axi_lite_strb_width_lp = axi_lite_data_width_p/8

   , localparam uce_mem_data_width_lp = `BSG_MAX(icache_fill_width_p, dcache_fill_width_p)
   `declare_bp_bedrock_mem_if_widths(paddr_width_p, uce_mem_data_width_lp, lce_id_width_p, lce_assoc_p, uce)
	 , localparam dma_pkt_width_lp = `bsg_cache_dma_pkt_width(caddr_width_p)
   )

  (input clk_i
  , input reset_i
 
	//========================Outgoing I/O========================
	, output logic [uce_mem_msg_width_lp-1:0]   io_cmd_o
	, output logic                              io_cmd_v_o
	, input                                     io_cmd_ready_and_i

	, input [uce_mem_msg_width_lp-1:0]          io_resp_i
	, input                                     io_resp_v_i
	, output logic                              io_resp_yumi_o

  //========================Incoming I/O========================
  , input [axi_lite_addr_width_p-1:0]         s_axi_lite_awaddr_i
  , input axi_prot_type_e                     s_axi_lite_awprot_i
  , input                                     s_axi_lite_awvalid_i
  , output logic                              s_axi_lite_awready_o

  , input [axi_lite_data_width_p-1:0]         s_axi_lite_wdata_i
  , input [axi_lite_strb_width_lp-1:0]        s_axi_lite_wstrb_i
  , input                                     s_axi_lite_wvalid_i
  , output logic                              s_axi_lite_wready_o

  , output axi_resp_type_e                    s_axi_lite_bresp_o 
  , output logic                              s_axi_lite_bvalid_o
  , input                                     s_axi_lite_bready_i

  , input [axi_lite_addr_width_p-1:0]         s_axi_lite_araddr_i
  , input axi_prot_type_e                     s_axi_lite_arprot_i
  , input                                     s_axi_lite_arvalid_i
  , output logic                              s_axi_lite_arready_o

  , output logic [axi_lite_data_width_p-1:0]  s_axi_lite_rdata_o
  , output axi_resp_type_e                    s_axi_lite_rresp_o
  , output logic                              s_axi_lite_rvalid_o
  , input                                     s_axi_lite_rready_i

  //======================DRAM Interface========================
	, output logic [dma_pkt_width_lp-1:0]       dma_pkt_o
	, output logic                              dma_pkt_v_o
	, input                                     dma_pkt_yumi_i

	, input [l2_fill_width_p-1:0]               dma_data_i
	, input                                     dma_data_v_i
	, output logic                              dma_data_ready_and_o

	, output logic [l2_fill_width_p-1:0]        dma_data_o
	, output logic                              dma_data_v_o
	, input                                     dma_data_yumi_i
	);

  // unicore declaration
  `declare_bp_bedrock_mem_if(paddr_width_p, uce_mem_data_width_lp, lce_id_width_p, lce_assoc_p, uce);
  bp_bedrock_uce_mem_msg_s io_cmd_li;
  bp_bedrock_uce_mem_msg_s io_resp_lo;
  logic io_cmd_v_li, io_cmd_yumi_lo;
  logic io_resp_v_lo, io_resp_ready_li;
  
  bp_unicore
   #(.bp_params_p(bp_params_p))
   unicore
   (.clk_i(clk_i)
    ,.reset_i(reset_i)

    // Outgoing I/O
    ,.io_cmd_o(io_cmd_o)
    ,.io_cmd_v_o(io_cmd_v_o)
    ,.io_cmd_ready_and_i(io_cmd_ready_and_i)

    ,.io_resp_i(io_resp_i)
    ,.io_resp_v_i(io_resp_v_i)
    ,.io_resp_yumi_o(io_resp_yumi_o)

    // Incoming I/O
    ,.io_cmd_i(io_cmd_li)
    ,.io_cmd_v_i(io_cmd_v_li)
    ,.io_cmd_yumi_o(io_cmd_yumi_lo)

    ,.io_resp_o(io_resp_lo) 
    ,.io_resp_v_o(io_resp_v_lo)
    ,.io_resp_ready_and_i(io_resp_ready_li)

    ,.dma_pkt_o(dma_pkt_o)
    ,.dma_pkt_v_o(dma_pkt_v_o)
    ,.dma_pkt_yumi_i(dma_pkt_yumi_i)

    ,.dma_data_i(dma_data_i)
    ,.dma_data_v_i(dma_data_v_i)
    ,.dma_data_ready_and_o(dma_data_ready_and_o)

    ,.dma_data_o(dma_data_o)
    ,.dma_data_v_o(dma_data_v_o)
    ,.dma_data_yumi_i(dma_data_yumi_i)
    );
  
  // incoming io wrapper
  axi_lite_to_bp_lite_client
   #(.bp_params_p(bp_params_p)
     ,.axi_data_width_p(axi_lite_data_width_p)
     ,.axi_addr_width_p(axi_lite_addr_width_p)
     )
   axil2io
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.io_cmd_o(io_cmd_li)
     ,.io_cmd_v_o(io_cmd_v_li)
     ,.io_cmd_yumi_i(io_cmd_yumi_lo)

     ,.io_resp_i(io_resp_lo)
     ,.io_resp_v_i(io_resp_v_lo)
     ,.io_resp_ready_o(io_resp_ready_li)

     ,.lce_id_i(lce_id_width_p'('b10))
     ,.*
     );

endmodule

