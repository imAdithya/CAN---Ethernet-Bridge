//////////////////////////////////////////////////////////////////////
////                                                              ////
////  bridge_regs.v                                               ////
////                                                              ////
////  Configuration register file for the CAN-Ethernet bridge.    ////
////  Wishbone slave interface. Hybrid defaults — works without   ////
////  CPU, fully overridable at runtime.                          ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "can_eth_bridge_defines.v"

module bridge_regs (
    input         clk,
    input         rst_n,

    //------------------------------------------------------
    // Wishbone Slave (host CPU access)
    //------------------------------------------------------
    input   [7:0] wb_adr_i,
    input  [31:0] wb_dat_i,
    output reg [31:0] wb_dat_o,
    input         wb_cyc_i,
    input         wb_stb_i,
    input         wb_we_i,
    output reg    wb_ack_o,

    //------------------------------------------------------
    // Configuration outputs (to upstream/downstream)
    //------------------------------------------------------
    output        bridge_en,
    output  [1:0] bridge_mode,      // 01=gateway, 10=tunnel
    output [47:0] dst_mac,
    output [47:0] src_mac,
    output        filter_en,
    output        filter_mode,
    output [28:0] filter_table_0,
    output [28:0] filter_table_1,
    output [28:0] filter_table_2,
    output [28:0] filter_table_3,
    output [28:0] filter_table_4,
    output [28:0] filter_table_5,
    output [28:0] filter_table_6,
    output [28:0] filter_table_7,
    output [28:0] filter_table_8,
    output [28:0] filter_table_9,
    output [28:0] filter_table_10,
    output [28:0] filter_table_11,
    output [28:0] filter_table_12,
    output [28:0] filter_table_13,
    output [28:0] filter_table_14,
    output [28:0] filter_table_15,
    output [31:0] tx_bd_addr,
    output [31:0] rx_bd_addr,

    //------------------------------------------------------
    // Status inputs (from upstream/downstream)
    //------------------------------------------------------
    input         cnt_can_rx_inc,
    input         cnt_eth_tx_inc,
    input         cnt_eth_rx_inc,
    input         cnt_can_tx_inc,
    input         cnt_filtered_inc,
    input         cnt_errors_inc,
    input   [3:0] queue_depth,
    input         upstream_busy,
    input         downstream_busy,

    //------------------------------------------------------
    // Tunnel sequence number
    //------------------------------------------------------
    output [15:0] tunnel_seq,
    input         tunnel_seq_inc
);

    //==========================================================
    // Register storage
    //==========================================================
    reg [31:0] r_bridge_ctrl;
    reg [31:0] r_dst_mac_hi;
    reg [31:0] r_dst_mac_lo;
    reg [31:0] r_src_mac_hi;
    reg [31:0] r_src_mac_lo;
    reg [31:0] r_filter_ctrl;
    reg [31:0] r_filter_table [0:15];
    reg [31:0] r_tx_bd_addr;
    reg [31:0] r_rx_bd_addr;

    // Status counters (read-only, clear-on-read optional)
    reg [31:0] r_cnt_can_rx;
    reg [31:0] r_cnt_eth_tx;
    reg [31:0] r_cnt_eth_rx;
    reg [31:0] r_cnt_can_tx;
    reg [31:0] r_cnt_filtered;
    reg [31:0] r_cnt_errors;

    // Tunnel sequence
    reg [15:0] r_tunnel_seq;

    //==========================================================
    // Output assignments
    //==========================================================
    assign bridge_en   = r_bridge_ctrl[0];
    assign bridge_mode = r_bridge_ctrl[2:1];
    assign dst_mac     = {r_dst_mac_hi, r_dst_mac_lo[15:0]};
    assign src_mac     = {r_src_mac_hi, r_src_mac_lo[15:0]};
    assign filter_en   = r_filter_ctrl[0];
    assign filter_mode = r_filter_ctrl[1];
    assign tx_bd_addr  = r_tx_bd_addr;
    assign rx_bd_addr  = r_rx_bd_addr;
    assign tunnel_seq  = r_tunnel_seq;

    assign filter_table_0  = r_filter_table[ 0][28:0];
    assign filter_table_1  = r_filter_table[ 1][28:0];
    assign filter_table_2  = r_filter_table[ 2][28:0];
    assign filter_table_3  = r_filter_table[ 3][28:0];
    assign filter_table_4  = r_filter_table[ 4][28:0];
    assign filter_table_5  = r_filter_table[ 5][28:0];
    assign filter_table_6  = r_filter_table[ 6][28:0];
    assign filter_table_7  = r_filter_table[ 7][28:0];
    assign filter_table_8  = r_filter_table[ 8][28:0];
    assign filter_table_9  = r_filter_table[ 9][28:0];
    assign filter_table_10 = r_filter_table[10][28:0];
    assign filter_table_11 = r_filter_table[11][28:0];
    assign filter_table_12 = r_filter_table[12][28:0];
    assign filter_table_13 = r_filter_table[13][28:0];
    assign filter_table_14 = r_filter_table[14][28:0];
    assign filter_table_15 = r_filter_table[15][28:0];

    //==========================================================
    // Wishbone Acknowledge
    //==========================================================
    wire wb_valid = wb_cyc_i & wb_stb_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= wb_valid & ~wb_ack_o;  // 1-cycle ack
    end

    //==========================================================
    // Register Write (with hybrid defaults)
    //==========================================================
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Hybrid defaults — bridge works without CPU
            r_bridge_ctrl <= `DEFAULT_BRIDGE_CTRL;
            r_dst_mac_hi  <= `DEFAULT_DST_MAC_HI;
            r_dst_mac_lo  <= `DEFAULT_DST_MAC_LO;
            r_src_mac_hi  <= `DEFAULT_SRC_MAC_HI;
            r_src_mac_lo  <= `DEFAULT_SRC_MAC_LO;
            r_filter_ctrl <= `DEFAULT_FILTER_CTRL;
            r_tx_bd_addr  <= `DEFAULT_TX_BD_ADDR;
            r_rx_bd_addr  <= `DEFAULT_RX_BD_ADDR;
            for (i = 0; i < 16; i = i + 1)
                r_filter_table[i] <= 32'h0;
        end else if (wb_valid && wb_we_i && !wb_ack_o) begin
            case (wb_adr_i)
                `REG_BRIDGE_CTRL:  r_bridge_ctrl <= wb_dat_i;
                `REG_DST_MAC_HI:   r_dst_mac_hi  <= wb_dat_i;
                `REG_DST_MAC_LO:   r_dst_mac_lo  <= wb_dat_i;
                `REG_SRC_MAC_HI:   r_src_mac_hi  <= wb_dat_i;
                `REG_SRC_MAC_LO:   r_src_mac_lo  <= wb_dat_i;
                `REG_FILTER_CTRL:  r_filter_ctrl <= wb_dat_i;
                `REG_TX_BD_ADDR:   r_tx_bd_addr  <= wb_dat_i;
                `REG_RX_BD_ADDR:   r_rx_bd_addr  <= wb_dat_i;
                default: begin
                    // Filter table: addresses 0x1C to 0x58 (16 entries × 4 bytes)
                    if (wb_adr_i >= `REG_FILTER_TBL_BASE &&
                        wb_adr_i <= `REG_FILTER_TBL_END) begin
                        r_filter_table[(wb_adr_i - `REG_FILTER_TBL_BASE) >> 2] <= wb_dat_i;
                    end
                end
            endcase
        end
    end

    //==========================================================
    // Register Read
    //==========================================================
    always @(*) begin
        case (wb_adr_i)
            `REG_BRIDGE_CTRL:  wb_dat_o = r_bridge_ctrl;
            `REG_BRIDGE_STATUS: wb_dat_o = {16'b0, queue_depth, 10'b0, downstream_busy, upstream_busy};
            `REG_DST_MAC_HI:   wb_dat_o = r_dst_mac_hi;
            `REG_DST_MAC_LO:   wb_dat_o = r_dst_mac_lo;
            `REG_SRC_MAC_HI:   wb_dat_o = r_src_mac_hi;
            `REG_SRC_MAC_LO:   wb_dat_o = r_src_mac_lo;
            `REG_FILTER_CTRL:  wb_dat_o = r_filter_ctrl;
            `REG_CNT_CAN_RX:   wb_dat_o = r_cnt_can_rx;
            `REG_CNT_ETH_TX:   wb_dat_o = r_cnt_eth_tx;
            `REG_CNT_ETH_RX:   wb_dat_o = r_cnt_eth_rx;
            `REG_CNT_CAN_TX:   wb_dat_o = r_cnt_can_tx;
            `REG_CNT_FILTERED: wb_dat_o = r_cnt_filtered;
            `REG_CNT_ERRORS:   wb_dat_o = r_cnt_errors;
            `REG_TUNNEL_SEQ:   wb_dat_o = {16'b0, r_tunnel_seq};
            `REG_TX_BD_ADDR:   wb_dat_o = r_tx_bd_addr;
            `REG_RX_BD_ADDR:   wb_dat_o = r_rx_bd_addr;
            default: begin
                if (wb_adr_i >= `REG_FILTER_TBL_BASE &&
                    wb_adr_i <= `REG_FILTER_TBL_END)
                    wb_dat_o = r_filter_table[(wb_adr_i - `REG_FILTER_TBL_BASE) >> 2];
                else
                    wb_dat_o = 32'h0;
            end
        endcase
    end

    //==========================================================
    // Status Counters (increment on pulse from datapath)
    //==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_cnt_can_rx   <= 32'h0;
            r_cnt_eth_tx   <= 32'h0;
            r_cnt_eth_rx   <= 32'h0;
            r_cnt_can_tx   <= 32'h0;
            r_cnt_filtered <= 32'h0;
            r_cnt_errors   <= 32'h0;
        end else begin
            if (cnt_can_rx_inc)   r_cnt_can_rx   <= r_cnt_can_rx   + 1'b1;
            if (cnt_eth_tx_inc)   r_cnt_eth_tx   <= r_cnt_eth_tx   + 1'b1;
            if (cnt_eth_rx_inc)   r_cnt_eth_rx   <= r_cnt_eth_rx   + 1'b1;
            if (cnt_can_tx_inc)   r_cnt_can_tx   <= r_cnt_can_tx   + 1'b1;
            if (cnt_filtered_inc) r_cnt_filtered <= r_cnt_filtered + 1'b1;
            if (cnt_errors_inc)   r_cnt_errors   <= r_cnt_errors   + 1'b1;
        end
    end

    //==========================================================
    // Tunnel Sequence Number (auto-increment)
    //==========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_tunnel_seq <= 16'h0;
        else if (tunnel_seq_inc)
            r_tunnel_seq <= r_tunnel_seq + 1'b1;
    end

endmodule
