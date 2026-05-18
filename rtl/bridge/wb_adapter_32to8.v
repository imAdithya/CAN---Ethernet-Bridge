//////////////////////////////////////////////////////////////////////
////                                                              ////
////  wb_adapter_32to8.v                                          ////
////                                                              ////
////  Wishbone bus width adapter: 32-bit master to 8-bit slave.   ////
////  Simple passthrough — lowest byte lane only.                  ////
////  Used to connect the bridge to the CAN controller.           ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

module wb_adapter_32to8 (
    // 32-bit master side (from bridge arbiter)
    input  [31:0] wbm_adr_i,
    input  [31:0] wbm_dat_i,
    output [31:0] wbm_dat_o,
    input         wbm_cyc_i,
    input         wbm_stb_i,
    input         wbm_we_i,
    output        wbm_ack_o,

    // 8-bit slave side (to CAN controller)
    output  [7:0] wbs_adr_o,
    output  [7:0] wbs_dat_o,
    input   [7:0] wbs_dat_i,
    output        wbs_cyc_o,
    output        wbs_stb_o,
    output        wbs_we_o,
    input         wbs_ack_i
);

    // Address: simple passthrough of lower 8 bits
    assign wbs_adr_o = wbm_adr_i[7:0];

    // Data: only lowest byte lane used
    assign wbs_dat_o = wbm_dat_i[7:0];
    assign wbm_dat_o = {24'b0, wbs_dat_i};

    // Control: direct passthrough
    assign wbs_cyc_o = wbm_cyc_i;
    assign wbs_stb_o = wbm_stb_i;
    assign wbs_we_o  = wbm_we_i;
    assign wbm_ack_o = wbs_ack_i;

endmodule
