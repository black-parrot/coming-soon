
`include "bp_common_defines.svh"
`include "bp_me_defines.svh"

module bp_lite_to_axi_lite_master
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
  input                                       clk_i
  , input                                     reset_i

  //==================== BP-LITE SIGNALS ======================
  , input [cce_mem_msg_width_lp-1:0]          io_cmd_i
  , input                                     io_cmd_v_i
  , output logic                              io_cmd_ready_o

  , output logic [cce_mem_msg_width_lp-1:0]   io_resp_o
  , output logic                              io_resp_v_o
  , input                                     io_resp_yumi_i

  //====================== AXI-4 LITE =========================
  // WRITE ADDRESS CHANNEL SIGNALS
  , output logic [axi_addr_width_p-1:0]       m_axi_lite_awaddr_o
  , output axi_prot_type_e                    m_axi_lite_awprot_o
  , output logic                              m_axi_lite_awvalid_o
  , input                                     m_axi_lite_awready_i

  // WRITE DATA CHANNEL SIGNALS
  , output logic [axi_data_width_p-1:0]       m_axi_lite_wdata_o
  , output logic [axi_strb_width_lp-1:0]      m_axi_lite_wstrb_o
  , output logic                              m_axi_lite_wvalid_o
  , input                                     m_axi_lite_wready_i

  // WRITE RESPONSE CHANNEL SIGNALS
  , input axi_resp_type_e                     m_axi_lite_bresp_i   
  , input                                     m_axi_lite_bvalid_i   
  , output logic                              m_axi_lite_bready_o

  // READ ADDRESS CHANNEL SIGNALS
  , output logic [axi_addr_width_p-1:0]       m_axi_lite_araddr_o
  , output axi_prot_type_e                    m_axi_lite_arprot_o
  , output logic                              m_axi_lite_arvalid_o
  , input                                     m_axi_lite_arready_i

  // READ DATA CHANNEL SIGNALS
  , input [axi_data_width_p-1:0]              m_axi_lite_rdata_i
  , input axi_resp_type_e                     m_axi_lite_rresp_i
  , input                                     m_axi_lite_rvalid_i
  , output logic                              m_axi_lite_rready_o
  );

  // declaring i/o command and response struct type and size
  `declare_bp_bedrock_mem_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, cce);

  // io cmd and resp structure cast
  bp_bedrock_cce_mem_msg_s io_cmd_cast_i, io_resp_cast_o;

  assign io_cmd_cast_i = io_cmd_i;
  assign io_resp_o     = io_resp_cast_o;

  // storing io cmd header
  bp_bedrock_cce_mem_msg_header_s io_cmd_header_r;

  bsg_dff_reset_en
   #(.width_p(cce_mem_msg_header_width_lp))
   mem_header_reg
    (.clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.en_i(io_cmd_v_i)
    ,.data_i(io_cmd_cast_i.header)
    ,.data_o(io_cmd_header_r)
    );

  // io cmd read/write validity
  wire io_cmd_w_v = io_cmd_v_i & (io_cmd_cast_i.header.msg_type == e_bedrock_mem_uc_wr);
  wire io_cmd_r_v = io_cmd_v_i & (io_cmd_cast_i.header.msg_type == e_bedrock_mem_uc_rd);

  // declaring all possible states
  enum {e_wait, e_read_data_tx, e_write_resp_rx} state_r, state_n;

  // combinational Logic
  always_comb 
    begin

      // BP IO
      io_cmd_ready_o       = m_axi_lite_wready_i;
      io_resp_cast_o       = '{header: io_cmd_header_r, data: '0};
      io_resp_v_o          = '0;

      // WRITE ADDRESS CHANNEL SIGNALS
      m_axi_lite_awaddr_o  = io_cmd_cast_i.header.addr[axi_addr_width_p-1:0];
      m_axi_lite_awprot_o  = e_axi_prot_default;
      m_axi_lite_awvalid_o = io_cmd_w_v;

      // WRITE DATA CHANNEL SIGNALS
      m_axi_lite_wdata_o   = io_cmd_cast_i.data[axi_data_width_p-1:0];
      m_axi_lite_wvalid_o  = io_cmd_w_v;

      // READ ADDRESS CHANNEL SIGNALS
      m_axi_lite_araddr_o  = io_cmd_cast_i.header.addr[axi_addr_width_p-1:0];
      m_axi_lite_arprot_o  = e_axi_prot_default;
      m_axi_lite_arvalid_o = io_cmd_r_v;

      // READ DATA CHANNEL SIGNALS
      m_axi_lite_rready_o  = io_resp_yumi_i;

      // WRITE RESPONSE CHANNEL SIGNALS
      m_axi_lite_bready_o  = 1'b1;

      // other logic
      state_n              = state_r;

      case(io_cmd_cast_i.header.size)
        e_bedrock_msg_size_1 : m_axi_lite_wstrb_o = axi_strb_width_lp'('h1);
        e_bedrock_msg_size_2 : m_axi_lite_wstrb_o = axi_strb_width_lp'('h3);
        e_bedrock_msg_size_4 : m_axi_lite_wstrb_o = axi_strb_width_lp'('hF);
        e_bedrock_msg_size_8 : m_axi_lite_wstrb_o = axi_strb_width_lp'('hFF);
        default              : m_axi_lite_wstrb_o = axi_strb_width_lp'('h0);
      endcase

      case(state_r) 
        e_wait : begin
          // if the client device is ready to receive, send the data along with the address   

          if (io_cmd_w_v & m_axi_lite_awready_i)
            state_n        = e_write_resp_rx;

          // if the io_cmd read is valid and client device read address channel is ready to receive
          // pass the valid read data to io_resp channel if io_resp is ready
          else if (io_cmd_r_v & m_axi_lite_arready_i) 
            begin
              io_resp_v_o                               = m_axi_lite_rvalid_i;	
              io_resp_cast_o.data[axi_data_width_p-1:0] = (m_axi_lite_rresp_i == '0)
                                                        ? m_axi_lite_rdata_i
                                                        : '0;

              state_n                                   = (io_resp_yumi_i)
                                                        ? e_wait
                                                        : e_read_data_tx;
            end
        end

        e_write_resp_rx : begin
          io_resp_cast_o.data[axi_data_width_p-1:0] = '0;
          io_resp_v_o                               = m_axi_lite_bvalid_i;
          state_n                                   = m_axi_lite_bvalid_i
                                                    ? e_wait
                                                    : state_r;
        end

       e_read_data_tx : begin
         io_resp_v_o                               = m_axi_lite_rvalid_i;	
         io_resp_cast_o.data[axi_data_width_p-1:0] = (m_axi_lite_rresp_i == '0)
                                                   ? m_axi_lite_rdata_i
                                                   : '0;

         state_n                                   = (io_resp_yumi_i)
                                                   ? e_wait
                                                   : state_r;
       end

      endcase
    end

  // Sequential Logic
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
      assert (axi_data_width_p==64 || axi_data_width_p==32) else $error("AXI4-LITE only supports a data width of 32 or 64bits");
      // give a warning if the client device has an error response
      if (m_axi_lite_rvalid_i) 
        assert (m_axi_lite_rresp_i == '0) else $warning("Client device has an error response to reads");
      if (m_axi_lite_bvalid_i)
        assert (m_axi_lite_bresp_i == '0) else $warning("Client device has an error response to writes");
    end
  //synopsys translate_on
endmodule
