//////////////////////////////////////////////////////////////////////
////                                                              ////
////  can_eth_bridge_top.v                                        ////
////                                                              ////
////  Top-level module for the CAN-Ethernet Bridge IP core.       ////
////  Integrates upstream/downstream paths, config registers,     ////
////  bus arbiter, and bus adapter.                                ////
////                                                              ////
////  External connections (at SoC level):                         ////
////    - CAN WB master port → WB adapter → CAN controller        ////
////    - ETH WB master port → ETH MAC slave + Shared RAM         ////
////    - Host WB slave port → optional RISC-V CPU                ////
////    - DPRAM is external (SoC level)                           ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "can_eth_bridge_defines.v"

module can_eth_bridge_top (
    input         clk,
    input         rst_n,

    //------------------------------------------------------
    // CAN Wishbone Master (8-bit, to CAN controller)
    //------------------------------------------------------
    output  [7:0] can_wbm_adr_o,
    output  [7:0] can_wbm_dat_o,
    input   [7:0] can_wbm_dat_i,
    output        can_wbm_cyc_o,
    output        can_wbm_stb_o,
    output        can_wbm_we_o,
    input         can_wbm_ack_i,

    //------------------------------------------------------
    // ETH Wishbone Master (32-bit, to ETH MAC + RAM)
    //------------------------------------------------------
    output [31:0] eth_wbm_adr_o,
    output [31:0] eth_wbm_dat_o,
    input  [31:0] eth_wbm_dat_i,
    output  [3:0] eth_wbm_sel_o,
    output        eth_wbm_cyc_o,
    output        eth_wbm_stb_o,
    output        eth_wbm_we_o,
    input         eth_wbm_ack_i,

    //------------------------------------------------------
    // Host Wishbone Slave (32-bit, from CPU — optional)
    //------------------------------------------------------
    input   [7:0] host_wb_adr_i,
    input  [31:0] host_wb_dat_i,
    output [31:0] host_wb_dat_o,
    input         host_wb_cyc_i,
    input         host_wb_stb_i,
    input         host_wb_we_i,
    output        host_wb_ack_o,

    //------------------------------------------------------
    // Interrupts
    //------------------------------------------------------
    input         can_irq_i,       // CAN RX interrupt
    input         eth_tx_irq_i,    // ETH TX complete
    input         eth_rx_irq_i,    // ETH RX complete
    input         can_tx_irq_i     // CAN TX complete
);

    //==========================================================
    // Configuration wires (from bridge_regs)
    //==========================================================
    wire        bridge_en;
    wire  [1:0] bridge_mode;
    wire [47:0] dst_mac;
    wire [47:0] src_mac;
    wire        filter_en;
    wire        filter_mode;
    wire [28:0] ft0, ft1, ft2, ft3, ft4, ft5, ft6, ft7;
    wire [28:0] ft8, ft9, ft10, ft11, ft12, ft13, ft14, ft15;
    wire [31:0] tx_bd_addr;
    wire [31:0] rx_bd_addr;
    wire [15:0] tunnel_seq;

    // Status wires
    wire        up_busy, dn_busy;
    wire        cnt_can_rx_inc, cnt_eth_tx_inc;
    wire        cnt_eth_rx_inc, cnt_can_tx_inc;
    wire        cnt_filtered_inc, cnt_errors_up, cnt_errors_dn;
    wire        tunnel_seq_inc;
    wire  [3:0] queue_depth;

    //==========================================================
    // Timestamp Counter (prescaled, 20 µs resolution)
    //==========================================================
    reg  [9:0]  ts_prescaler;
    reg [15:0]  timestamp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts_prescaler <= 10'd0;
            timestamp    <= 16'd0;
        end else begin
            if (ts_prescaler == `TIMESTAMP_PRESCALE) begin
                ts_prescaler <= 10'd0;
                timestamp    <= timestamp + 1'b1;
            end else begin
                ts_prescaler <= ts_prescaler + 1'b1;
            end
        end
    end

    //==========================================================
    // Bridge Configuration Registers
    //==========================================================
    bridge_regs u_regs (
        .clk              (clk),
        .rst_n            (rst_n),
        .wb_adr_i         (host_wb_adr_i),
        .wb_dat_i         (host_wb_dat_i),
        .wb_dat_o         (host_wb_dat_o),
        .wb_cyc_i         (host_wb_cyc_i),
        .wb_stb_i         (host_wb_stb_i),
        .wb_we_i          (host_wb_we_i),
        .wb_ack_o         (host_wb_ack_o),
        .bridge_en        (bridge_en),
        .bridge_mode      (bridge_mode),
        .dst_mac          (dst_mac),
        .src_mac          (src_mac),
        .filter_en        (filter_en),
        .filter_mode      (filter_mode),
        .filter_table_0   (ft0),   .filter_table_1  (ft1),
        .filter_table_2   (ft2),   .filter_table_3  (ft3),
        .filter_table_4   (ft4),   .filter_table_5  (ft5),
        .filter_table_6   (ft6),   .filter_table_7  (ft7),
        .filter_table_8   (ft8),   .filter_table_9  (ft9),
        .filter_table_10  (ft10),  .filter_table_11 (ft11),
        .filter_table_12  (ft12),  .filter_table_13 (ft13),
        .filter_table_14  (ft14),  .filter_table_15 (ft15),
        .tx_bd_addr       (tx_bd_addr),
        .rx_bd_addr       (rx_bd_addr),
        .cnt_can_rx_inc   (cnt_can_rx_inc),
        .cnt_eth_tx_inc   (cnt_eth_tx_inc),
        .cnt_eth_rx_inc   (cnt_eth_rx_inc),
        .cnt_can_tx_inc   (cnt_can_tx_inc),
        .cnt_filtered_inc (cnt_filtered_inc),
        .cnt_errors_inc   (cnt_errors_up | cnt_errors_dn),
        .queue_depth      (queue_depth),
        .upstream_busy    (up_busy),
        .downstream_busy  (dn_busy),
        .tunnel_seq       (tunnel_seq),
        .tunnel_seq_inc   (tunnel_seq_inc)
    );

    //==========================================================
    // Arbiter internal wires
    //==========================================================
    // Upstream CAN bus
    wire        up_can_req, up_can_gnt;
    wire [31:0] up_can_adr, up_can_dat_o;
    wire        up_can_we, up_can_cyc, up_can_stb;
    wire [31:0] up_can_dat_i;
    wire        up_can_ack;

    // Downstream CAN bus
    wire        dn_can_req, dn_can_gnt;
    wire [31:0] dn_can_adr, dn_can_dat_o;
    wire        dn_can_we, dn_can_cyc, dn_can_stb;
    wire [31:0] dn_can_dat_i;
    wire        dn_can_ack;

    // Upstream ETH bus
    wire        up_eth_req, up_eth_gnt;
    wire [31:0] up_eth_adr, up_eth_dat_o;
    wire  [3:0] up_eth_sel;
    wire        up_eth_we, up_eth_cyc, up_eth_stb;
    wire [31:0] up_eth_dat_i;
    wire        up_eth_ack;

    // Downstream ETH bus
    wire        dn_eth_req, dn_eth_gnt;
    wire [31:0] dn_eth_adr, dn_eth_dat_o;
    wire  [3:0] dn_eth_sel;
    wire        dn_eth_we, dn_eth_cyc, dn_eth_stb;
    wire [31:0] dn_eth_dat_i;
    wire        dn_eth_ack;

    // Arbiter output to CAN adapter (32-bit side)
    wire [31:0] arb_can_adr, arb_can_dat_o;
    wire        arb_can_we, arb_can_cyc, arb_can_stb;
    wire [31:0] arb_can_dat_i;
    wire        arb_can_ack;

    //==========================================================
    // Upstream Path
    //==========================================================
    bridge_upstream u_upstream (
        .clk              (clk),
        .rst_n            (rst_n),
        .bridge_en        (bridge_en),
        .bridge_mode      (bridge_mode),
        .can_irq_i        (can_irq_i),
        .eth_tx_irq_i     (eth_tx_irq_i),
        .dst_mac          (dst_mac),
        .src_mac          (src_mac),
        .filter_en        (filter_en),
        .filter_mode      (filter_mode),
        .filter_table_0   (ft0),   .filter_table_1  (ft1),
        .filter_table_2   (ft2),   .filter_table_3  (ft3),
        .filter_table_4   (ft4),   .filter_table_5  (ft5),
        .filter_table_6   (ft6),   .filter_table_7  (ft7),
        .filter_table_8   (ft8),   .filter_table_9  (ft9),
        .filter_table_10  (ft10),  .filter_table_11 (ft11),
        .filter_table_12  (ft12),  .filter_table_13 (ft13),
        .filter_table_14  (ft14),  .filter_table_15 (ft15),
        .tx_bd_addr       (tx_bd_addr),
        .tunnel_seq       (tunnel_seq),
        .timestamp        (timestamp),
        .can_wb_req       (up_can_req),
        .can_wb_gnt       (up_can_gnt),
        .can_wb_adr       (up_can_adr),
        .can_wb_dat_o     (up_can_dat_o),
        .can_wb_we        (up_can_we),
        .can_wb_cyc       (up_can_cyc),
        .can_wb_stb       (up_can_stb),
        .can_wb_dat_i     (up_can_dat_i),
        .can_wb_ack       (up_can_ack),
        .eth_wb_req       (up_eth_req),
        .eth_wb_gnt       (up_eth_gnt),
        .eth_wb_adr       (up_eth_adr),
        .eth_wb_dat_o     (up_eth_dat_o),
        .eth_wb_sel       (up_eth_sel),
        .eth_wb_we        (up_eth_we),
        .eth_wb_cyc       (up_eth_cyc),
        .eth_wb_stb       (up_eth_stb),
        .eth_wb_dat_i     (up_eth_dat_i),
        .eth_wb_ack       (up_eth_ack),
        .busy             (up_busy),
        .cnt_can_rx_inc   (cnt_can_rx_inc),
        .cnt_eth_tx_inc   (cnt_eth_tx_inc),
        .cnt_filtered_inc (cnt_filtered_inc),
        .cnt_errors_inc   (cnt_errors_up),
        .tunnel_seq_inc   (tunnel_seq_inc)
    );

    //==========================================================
    // Downstream Path
    //==========================================================
    bridge_downstream u_downstream (
        .clk              (clk),
        .rst_n            (rst_n),
        .bridge_en        (bridge_en),
        .bridge_mode      (bridge_mode),
        .eth_rx_irq_i     (eth_rx_irq_i),
        .can_tx_irq_i     (can_tx_irq_i),
        .rx_bd_addr       (rx_bd_addr),
        .can_wb_req       (dn_can_req),
        .can_wb_gnt       (dn_can_gnt),
        .can_wb_adr       (dn_can_adr),
        .can_wb_dat_o     (dn_can_dat_o),
        .can_wb_we        (dn_can_we),
        .can_wb_cyc       (dn_can_cyc),
        .can_wb_stb       (dn_can_stb),
        .can_wb_dat_i     (dn_can_dat_i),
        .can_wb_ack       (dn_can_ack),
        .eth_wb_req       (dn_eth_req),
        .eth_wb_gnt       (dn_eth_gnt),
        .eth_wb_adr       (dn_eth_adr),
        .eth_wb_dat_o     (dn_eth_dat_o),
        .eth_wb_sel       (dn_eth_sel),
        .eth_wb_we        (dn_eth_we),
        .eth_wb_cyc       (dn_eth_cyc),
        .eth_wb_stb       (dn_eth_stb),
        .eth_wb_dat_i     (dn_eth_dat_i),
        .eth_wb_ack       (dn_eth_ack),
        .busy             (dn_busy),
        .cnt_eth_rx_inc   (cnt_eth_rx_inc),
        .cnt_can_tx_inc   (cnt_can_tx_inc),
        .cnt_errors_inc   (cnt_errors_dn),
        .queue_depth      (queue_depth)
    );

    //==========================================================
    // Wishbone Arbiter
    //==========================================================
    wb_arbiter u_arbiter (
        .clk            (clk),
        .rst_n          (rst_n),
        // Upstream CAN
        .up_can_req     (up_can_req),
        .up_can_gnt     (up_can_gnt),
        .up_can_adr     (up_can_adr),
        .up_can_dat_o   (up_can_dat_o),
        .up_can_we      (up_can_we),
        .up_can_cyc     (up_can_cyc),
        .up_can_stb     (up_can_stb),
        .up_can_dat_i   (up_can_dat_i),
        .up_can_ack     (up_can_ack),
        // Downstream CAN
        .dn_can_req     (dn_can_req),
        .dn_can_gnt     (dn_can_gnt),
        .dn_can_adr     (dn_can_adr),
        .dn_can_dat_o   (dn_can_dat_o),
        .dn_can_we      (dn_can_we),
        .dn_can_cyc     (dn_can_cyc),
        .dn_can_stb     (dn_can_stb),
        .dn_can_dat_i   (dn_can_dat_i),
        .dn_can_ack     (dn_can_ack),
        // CAN bus output
        .can_adr_o      (arb_can_adr),
        .can_dat_o      (arb_can_dat_o),
        .can_we_o       (arb_can_we),
        .can_cyc_o      (arb_can_cyc),
        .can_stb_o      (arb_can_stb),
        .can_dat_i      (arb_can_dat_i),
        .can_ack_i      (arb_can_ack),
        // Upstream ETH
        .up_eth_req     (up_eth_req),
        .up_eth_gnt     (up_eth_gnt),
        .up_eth_adr     (up_eth_adr),
        .up_eth_dat_o   (up_eth_dat_o),
        .up_eth_sel     (up_eth_sel),
        .up_eth_we      (up_eth_we),
        .up_eth_cyc     (up_eth_cyc),
        .up_eth_stb     (up_eth_stb),
        .up_eth_dat_i   (up_eth_dat_i),
        .up_eth_ack     (up_eth_ack),
        // Downstream ETH
        .dn_eth_req     (dn_eth_req),
        .dn_eth_gnt     (dn_eth_gnt),
        .dn_eth_adr     (dn_eth_adr),
        .dn_eth_dat_o   (dn_eth_dat_o),
        .dn_eth_sel     (dn_eth_sel),
        .dn_eth_we      (dn_eth_we),
        .dn_eth_cyc     (dn_eth_cyc),
        .dn_eth_stb     (dn_eth_stb),
        .dn_eth_dat_i   (dn_eth_dat_i),
        .dn_eth_ack     (dn_eth_ack),
        // ETH bus output
        .eth_adr_o      (eth_wbm_adr_o),
        .eth_dat_o      (eth_wbm_dat_o),
        .eth_sel_o      (eth_wbm_sel_o),
        .eth_we_o       (eth_wbm_we_o),
        .eth_cyc_o      (eth_wbm_cyc_o),
        .eth_stb_o      (eth_wbm_stb_o),
        .eth_dat_i      (eth_wbm_dat_i),
        .eth_ack_i      (eth_wbm_ack_i)
    );

    //==========================================================
    // Wishbone Bus Width Adapter (32→8 for CAN)
    //==========================================================
    wb_adapter_32to8 u_adapter (
        // 32-bit side (from arbiter)
        .wbm_adr_i      (arb_can_adr),
        .wbm_dat_i      (arb_can_dat_o),
        .wbm_dat_o      (arb_can_dat_i),
        .wbm_cyc_i      (arb_can_cyc),
        .wbm_stb_i      (arb_can_stb),
        .wbm_we_i       (arb_can_we),
        .wbm_ack_o      (arb_can_ack),
        // 8-bit side (to CAN controller)
        .wbs_adr_o      (can_wbm_adr_o),
        .wbs_dat_o      (can_wbm_dat_o),
        .wbs_dat_i      (can_wbm_dat_i),
        .wbs_cyc_o      (can_wbm_cyc_o),
        .wbs_stb_o      (can_wbm_stb_o),
        .wbs_we_o       (can_wbm_we_o),
        .wbs_ack_i      (can_wbm_ack_i)
    );

endmodule
