//////////////////////////////////////////////////////////////////////
////                                                              ////
////  wb_arbiter.v                                                ////
////                                                              ////
////  Round-robin Wishbone arbiter for the CAN-Ethernet bridge.   ////
////  Arbitrates two requesters (upstream, downstream) for two    ////
////  shared buses (Master A = CAN, Master B = ETH/RAM).          ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

module wb_arbiter (
    input         clk,
    input         rst_n,

    //------------------------------------------------------
    // Master A (CAN bus) — Upstream requester
    //------------------------------------------------------
    input         up_can_req,
    output        up_can_gnt,
    input  [31:0] up_can_adr,
    input  [31:0] up_can_dat_o,
    input         up_can_we,
    input         up_can_cyc,
    input         up_can_stb,
    output [31:0] up_can_dat_i,
    output        up_can_ack,

    //------------------------------------------------------
    // Master A (CAN bus) — Downstream requester
    //------------------------------------------------------
    input         dn_can_req,
    output        dn_can_gnt,
    input  [31:0] dn_can_adr,
    input  [31:0] dn_can_dat_o,
    input         dn_can_we,
    input         dn_can_cyc,
    input         dn_can_stb,
    output [31:0] dn_can_dat_i,
    output        dn_can_ack,

    //------------------------------------------------------
    // Master A output (to WB adapter → CAN controller)
    //------------------------------------------------------
    output [31:0] can_adr_o,
    output [31:0] can_dat_o,
    output        can_we_o,
    output        can_cyc_o,
    output        can_stb_o,
    input  [31:0] can_dat_i,
    input         can_ack_i,

    //------------------------------------------------------
    // Master B (ETH/RAM bus) — Upstream requester
    //------------------------------------------------------
    input         up_eth_req,
    output        up_eth_gnt,
    input  [31:0] up_eth_adr,
    input  [31:0] up_eth_dat_o,
    input   [3:0] up_eth_sel,
    input         up_eth_we,
    input         up_eth_cyc,
    input         up_eth_stb,
    output [31:0] up_eth_dat_i,
    output        up_eth_ack,

    //------------------------------------------------------
    // Master B (ETH/RAM bus) — Downstream requester
    //------------------------------------------------------
    input         dn_eth_req,
    output        dn_eth_gnt,
    input  [31:0] dn_eth_adr,
    input  [31:0] dn_eth_dat_o,
    input   [3:0] dn_eth_sel,
    input         dn_eth_we,
    input         dn_eth_cyc,
    input         dn_eth_stb,
    output [31:0] dn_eth_dat_i,
    output        dn_eth_ack,

    //------------------------------------------------------
    // Master B output (to ETH MAC slave + Shared RAM)
    //------------------------------------------------------
    output [31:0] eth_adr_o,
    output [31:0] eth_dat_o,
    output  [3:0] eth_sel_o,
    output        eth_we_o,
    output        eth_cyc_o,
    output        eth_stb_o,
    input  [31:0] eth_dat_i,
    input         eth_ack_i
);

    //==========================================================
    // Master A (CAN) Arbitration
    //==========================================================
    reg can_owner;  // 0 = upstream, 1 = downstream
    localparam CAN_UP = 1'b0;
    localparam CAN_DN = 1'b1;

    // Grant logic: hold grant while cyc is active,
    // switch on deassert using round-robin
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            can_owner <= CAN_UP;
        end else begin
            case (can_owner)
                CAN_UP: begin
                    // If upstream releases bus and downstream wants it
                    if (!up_can_cyc && dn_can_req)
                        can_owner <= CAN_DN;
                end
                CAN_DN: begin
                    // If downstream releases bus and upstream wants it
                    if (!dn_can_cyc && up_can_req)
                        can_owner <= CAN_UP;
                end
            endcase
        end
    end

    assign up_can_gnt = (can_owner == CAN_UP);
    assign dn_can_gnt = (can_owner == CAN_DN);

    // Mux CAN bus signals
    assign can_adr_o = (can_owner == CAN_UP) ? up_can_adr : dn_can_adr;
    assign can_dat_o = (can_owner == CAN_UP) ? up_can_dat_o : dn_can_dat_o;
    assign can_we_o  = (can_owner == CAN_UP) ? up_can_we  : dn_can_we;
    assign can_cyc_o = (can_owner == CAN_UP) ? up_can_cyc : dn_can_cyc;
    assign can_stb_o = (can_owner == CAN_UP) ? up_can_stb : dn_can_stb;

    // Broadcast read data and ack (only granted master uses them)
    assign up_can_dat_i = can_dat_i;
    assign dn_can_dat_i = can_dat_i;
    assign up_can_ack   = can_ack_i & up_can_gnt;
    assign dn_can_ack   = can_ack_i & dn_can_gnt;

    //==========================================================
    // Master B (ETH/RAM) Arbitration
    //==========================================================
    reg eth_owner;  // 0 = upstream, 1 = downstream
    localparam ETH_UP = 1'b0;
    localparam ETH_DN = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eth_owner <= ETH_UP;
        end else begin
            case (eth_owner)
                ETH_UP: begin
                    if (!up_eth_cyc && dn_eth_req)
                        eth_owner <= ETH_DN;
                end
                ETH_DN: begin
                    if (!dn_eth_cyc && up_eth_req)
                        eth_owner <= ETH_UP;
                end
            endcase
        end
    end

    assign up_eth_gnt = (eth_owner == ETH_UP);
    assign dn_eth_gnt = (eth_owner == ETH_DN);

    // Mux ETH bus signals
    assign eth_adr_o = (eth_owner == ETH_UP) ? up_eth_adr : dn_eth_adr;
    assign eth_dat_o = (eth_owner == ETH_UP) ? up_eth_dat_o : dn_eth_dat_o;
    assign eth_sel_o = (eth_owner == ETH_UP) ? up_eth_sel : dn_eth_sel;
    assign eth_we_o  = (eth_owner == ETH_UP) ? up_eth_we  : dn_eth_we;
    assign eth_cyc_o = (eth_owner == ETH_UP) ? up_eth_cyc : dn_eth_cyc;
    assign eth_stb_o = (eth_owner == ETH_UP) ? up_eth_stb : dn_eth_stb;

    // Broadcast read data and ack
    assign up_eth_dat_i = eth_dat_i;
    assign dn_eth_dat_i = eth_dat_i;
    assign up_eth_ack   = eth_ack_i & up_eth_gnt;
    assign dn_eth_ack   = eth_ack_i & dn_eth_gnt;

endmodule
