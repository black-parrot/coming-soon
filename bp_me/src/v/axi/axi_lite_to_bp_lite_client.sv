
`include "bp_common_defines.svh"
`include "bp_me_defines.svh"

module axi_lite_to_bp_lite_client
 import bp_common_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
  `declare_bp_proc_params(bp_params_p)
  `declare_bp_bedrock_mem_if_widths(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, cce)

  // AXI WRITE DATA CHANNEL PARAMS
  , parameter  axi_data_width_p             = 32
  , localparam axi_strb_width_lp            = axi_data_width_p/8

  // AXI WRITE/READ ADDRESS CHANNEL PARAMS  
  , parameter axi_addr_width_p              = 32
  )

  (//==================== GLOBAL SIGNALS =======================
   input clk_i  
   , input reset_i

   //==================== BP-LITE SIGNALS ======================
   , input [lce_id_width_p-1:0]                 lce_id_i

   , output logic [cce_mem_msg_width_lp-1:0]    io_cmd_o
   , output logic                               io_cmd_v_o
   , input                                      io_cmd_yumi_i

   , input [cce_mem_msg_width_lp-1:0]           io_resp_i
   , input                                      io_resp_v_i
   , output logic                               io_resp_ready_o

   //====================== AXI-4 LITE =========================
   // WRITE ADDRESS CHANNEL SIGNALS
   , input [axi_addr_width_p-1:0]               s_axi_lite_awaddr_i
   , input axi_prot_type_e                      s_axi_lite_awprot_i
   , input                                      s_axi_lite_awvalid_i
   , output logic                               s_axi_lite_awready_o

   // WRITE DATA CHANNEL SIGNALS
   , input [axi_data_width_p-1:0]               s_axi_lite_wdata_i
   , input [axi_strb_width_lp-1:0]              s_axi_lite_wstrb_i
   , input                                      s_axi_lite_wvalid_i
   , output logic                               s_axi_lite_wready_o

   // WRITE RESPONSE CHANNEL SIGNALS
   , output axi_resp_type_e                     s_axi_lite_bresp_o   
   , output logic                               s_axi_lite_bvalid_o   
   , input                                      s_axi_lite_bready_i

   // READ ADDRESS CHANNEL SIGNALS
   , input [axi_addr_width_p-1:0]               s_axi_lite_araddr_i
   , input axi_prot_type_e                      s_axi_lite_arprot_i
   , input                                      s_axi_lite_arvalid_i
   , output logic                               s_axi_lite_arready_o

   // READ DATA CHANNEL SIGNALS
   , output logic [axi_data_width_p-1:0]        s_axi_lite_rdata_o
   , output axi_resp_type_e                     s_axi_lite_rresp_o
   , output logic                               s_axi_lite_rvalid_o
   , input                                      s_axi_lite_rready_i
  );

  wire [2:0] unused_0 = s_axi_lite_awprot_i;
  wire [2:0] unused_1 = s_axi_lite_arprot_i;

  // declaring i/o command and response struct type and size
  `declare_bp_bedrock_mem_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, cce);

  bp_bedrock_cce_mem_msg_s io_cmd_cast_o, io_resp_cast_i;
  bp_bedrock_cce_mem_payload_s io_cmd_cast_payload, io_resp_cast_payload;
  assign io_cmd_o       = io_cmd_cast_o;
  assign io_resp_cast_i = io_resp_i;

  // intermediate values for io_cmd_data_o resulted from a generate block
  logic [axi_data_width_p-1:0] io_cmd_data_lo;
  for (genvar i = 0; i < axi_strb_width_lp; i++) begin : io_cmd_data
    assign io_cmd_data_lo[i*8+:8] = (s_axi_lite_wstrb_i[i])
                                  ? s_axi_lite_wdata_i[i*8+:8]
                                  : 8'b0;
  end

  // axi client device read or write channel validity
  logic axi_lite_r_v, axi_lite_w_v;
  assign axi_lite_w_v = s_axi_lite_wvalid_i & s_axi_lite_awvalid_i;
  assign axi_lite_r_v = s_axi_lite_arvalid_i;

  // Declaring all possible states
  enum {e_wait, e_read_data_tx, e_write_resp} state_r, state_n;

  // Combinational Logic
  always_comb 
    begin
      // BP side
      io_cmd_cast_o        = '0;
			io_cmd_cast_payload  = '0;
      io_cmd_v_o           = '0;
      io_resp_ready_o      = (io_resp_cast_i.header.msg_type == e_bedrock_mem_uc_rd)
														 ? s_axi_lite_rready_i
														 : io_resp_v_i;

      // WRITE ADDRESS CHANNEL SIGNALS
      s_axi_lite_awready_o = '0;

      // WRITE DATA CHANNEL SIGNALS
      s_axi_lite_wready_o  = '0;

      // READ ADDRESS CHANNEL SIGNALS
      s_axi_lite_arready_o = '0;

      // READ DATA CHANNEL SIGNALS
      s_axi_lite_rdata_o   = '0;
      s_axi_lite_rresp_o   = e_axi_resp_okay;
      s_axi_lite_rvalid_o  = '0;

      // WRITE RESPONSE CHANNEL SIGNALS
      s_axi_lite_bresp_o   = e_axi_resp_okay;
      s_axi_lite_bvalid_o  = '0;

      // other logic
      state_n              = state_r;

      case (s_axi_lite_wstrb_i)
        axi_strb_width_lp'('h1)  : io_cmd_cast_o.header.size = e_bedrock_msg_size_1;
        axi_strb_width_lp'('h3)  : io_cmd_cast_o.header.size = e_bedrock_msg_size_2;
        axi_strb_width_lp'('hF)  : io_cmd_cast_o.header.size = e_bedrock_msg_size_4;
        axi_strb_width_lp'('hFF) : io_cmd_cast_o.header.size = e_bedrock_msg_size_8;
      endcase

      case (state_r) 
        e_wait : begin

          if (s_axi_lite_arvalid_i) 
            begin
              io_cmd_cast_payload.lce_id    = lce_id_i;
              io_cmd_cast_o.header.addr     = s_axi_lite_araddr_i;
              io_cmd_cast_o.header.msg_type = e_bedrock_mem_uc_rd;
	      			io_cmd_cast_o.header.payload  = io_cmd_cast_payload;
              io_cmd_v_o                    = axi_lite_r_v;
          
              state_n                       = (io_cmd_yumi_i & axi_lite_r_v)
                                            ? e_read_data_tx
                                            : state_r;
            end

          else if (s_axi_lite_awvalid_i) 
            begin
              io_cmd_cast_payload.lce_id               = lce_id_i;
              io_cmd_cast_o.header.addr                = s_axi_lite_awaddr_i;
              io_cmd_cast_o.header.msg_type            = e_bedrock_mem_uc_wr;
	      io_cmd_cast_o.header.payload             = io_cmd_cast_payload;
              io_cmd_cast_o.data[axi_data_width_p-1:0] = io_cmd_data_lo;
              io_cmd_v_o                               = axi_lite_w_v;
          
              state_n                                  = (io_cmd_yumi_i & axi_lite_w_v) 
                                                       ? e_write_resp
                                                       : state_r;
            end
        end

        e_write_resp : begin
          s_axi_lite_awready_o = 1'b1;
          s_axi_lite_wready_o  = 1'b1;

          s_axi_lite_bvalid_o = 1'b1;
          state_n             = (s_axi_lite_bready_i)
                              ? e_wait
                              : state_r;
        end

        e_read_data_tx : begin
          s_axi_lite_arready_o = 1'b1;
          s_axi_lite_rdata_o  = io_resp_cast_i.data[axi_data_width_p-1:0];
          s_axi_lite_rvalid_o = io_resp_v_i;
          state_n             = (s_axi_lite_rready_i)
                              ? e_wait
                              : state_r;
        end

      endcase
    end

  always_ff @(posedge clk_i) 
    begin
      if (reset_i)
        state_r <= e_wait;
      else
        state_r <= state_n;
    end

  //synopsys translate_off
  initial 
    begin
      assert (axi_data_width_p==64 || axi_data_width_p==32) else $error("AXI4-LITE only supports a data width of 32 or 64bits.");
      assert (s_axi_lite_awprot_i == 3'b000) else $info("AXI4-LITE access permission mode is not supported.");
    end
  //synopsys translate_on
endmodule
