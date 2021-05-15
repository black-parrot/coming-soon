`ifndef BP_ME_AXI_PKGDEF_SVH
`define BP_ME_AXI_PKGDEF_SVH

  typedef enum logic [1:0]
  {
    e_axi_resp_okay    = 2'b00

    // Unsupported
    //,e_axi_resp_exokay = 2'b01
    //,e_axi_resp_slverr = 2'b10
    //,e_axi_resp_decerr = 2'b11
  } axi_resp_type_e;

  // prot[0] : normal / privileged
  // prot[1] : secure / non-secure
  // prot[2] : data / instruction
  typedef enum logic [2:0]
  {
    // Normal / Non-Secure / Data
    e_axi_prot_default = 3'b000
    // All others unsupported
  } axi_prot_type_e;

  typedef enum logic [3:0]
  {
    e_axi_cache_normal_nc_bufferable = 4'b0011
    // All others unsupported
  } axi_cache_type_e;

  typedef enum logic [1:0]
  {
    e_axi_burst_fixed     = 2'b00
    ,e_axi_burst_incr     = 2'b01
    ,e_axi_burst_wrap     = 2'b10
    ,e_axi_burst_reserved = 2'b11
  } axi_burst_type_e;

  typedef enum logic [3:0]
  {
    e_axi_qos_none = 4'b0000
    // All others unsupported
  } axi_qos_type_e;

  typedef enum logic [2:0]
  {
    e_axi_size_1B    = 3'b000
    ,e_axi_size_2B   = 3'b001
    ,e_axi_size_4B   = 3'b010
    ,e_axi_size_8B   = 3'b011
    ,e_axi_size_16B  = 3'b100
    ,e_axi_size_32B  = 3'b101
    ,e_axi_size_64B  = 3'b110
    ,e_axi_size_128B = 3'b111
  } axi_size_e;

  typedef enum logic [3:0]
  {
    e_axi_len_1   = 4'b0000
    ,e_axi_len_2  = 4'b0001
    ,e_axi_len_3  = 4'b0010
    ,e_axi_len_4  = 4'b0011
    ,e_axi_len_5  = 4'b0100
    ,e_axi_len_6  = 4'b0101
    ,e_axi_len_7  = 4'b0110
    ,e_axi_len_8  = 4'b0111
    ,e_axi_len_9  = 4'b1000
    ,e_axi_len_10 = 4'b1001
    ,e_axi_len_11 = 4'b1010
    ,e_axi_len_12 = 4'b1011
    ,e_axi_len_13 = 4'b1100
    ,e_axi_len_14 = 4'b1101
    ,e_axi_len_15 = 4'b1110
    ,e_axi_len_16 = 4'b1111
  } axi_len_e;

`endif
