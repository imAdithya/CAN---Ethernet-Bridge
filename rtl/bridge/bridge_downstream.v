//////////////////////////////////////////////////////////////////////
////                                                              ////
////  bridge_downstream.v                                         ////
////                                                              ////
////  Downstream data path: Ethernet → CAN.                       ////
////  10-state FSM: IDLE → READ_BD → READ_RAM → VALIDATE →       ////
////  DECAP → QUEUE_CHK → ENQUEUE → WRITE_CAN →                  ////
////  WAIT_CAN_TX → FREE_BD                                       ////
////                                                              ////
////  Supports Gateway (0xCAFE) and Tunnel (0xCABE) modes.        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "can_eth_bridge_defines.v"

module bridge_downstream (
    input         clk,
    input         rst_n,

    // Control
    input         bridge_en,
    input   [1:0] bridge_mode,

    // Interrupts
    input         eth_rx_irq_i,    // ETH RX complete interrupt
    input         can_tx_irq_i,    // CAN TX complete interrupt

    // Configuration (from bridge_regs)
    input  [31:0] rx_bd_addr,

    // CAN WB Master (through arbiter)
    output reg    can_wb_req,
    input         can_wb_gnt,
    output reg [31:0] can_wb_adr,
    output reg [31:0] can_wb_dat_o,
    output reg    can_wb_we,
    output reg    can_wb_cyc,
    output reg    can_wb_stb,
    input  [31:0] can_wb_dat_i,
    input         can_wb_ack,

    // ETH WB Master (through arbiter)
    output reg    eth_wb_req,
    input         eth_wb_gnt,
    output reg [31:0] eth_wb_adr,
    output reg [31:0] eth_wb_dat_o,
    output reg  [3:0] eth_wb_sel,
    output reg    eth_wb_we,
    output reg    eth_wb_cyc,
    output reg    eth_wb_stb,
    input  [31:0] eth_wb_dat_i,
    input         eth_wb_ack,

    // Status
    output        busy,
    output reg    cnt_eth_rx_inc,
    output reg    cnt_can_tx_inc,
    output reg    cnt_errors_inc,
    output  [3:0] queue_depth
);

    //==========================================================
    // FSM State Register
    //==========================================================
    reg [3:0] state;
    assign busy = (state != `DN_IDLE);

    //==========================================================
    // Internal Registers — RX Buffer Descriptor
    //==========================================================
    reg [31:0] rx_bd_status_reg;
    reg [31:0] rx_bd_ptr_reg;

    //==========================================================
    // Internal Registers — RX Frame Buffer
    //==========================================================
    reg [31:0] rx_frame_buf [0:`FRAME_WORDS-1];

    //==========================================================
    // Internal Registers — Extracted CAN Frame
    //==========================================================
    reg [28:0] rx_can_id;
    reg  [3:0] rx_can_dlc;
    reg        rx_can_eff;
    reg        rx_can_rtr;
    reg [63:0] rx_can_data;

    //==========================================================
    // Counters
    //==========================================================
    reg  [4:0] word_cnt;
    reg  [3:0] byte_cnt;
    reg  [1:0] bd_cnt;

    //==========================================================
    // CAN TX Queue Instance
    //==========================================================
    reg        queue_push;
    reg        queue_pop;
    wire       queue_full;
    wire       queue_empty;

    wire [28:0] q_out_id;
    wire  [3:0] q_out_dlc;
    wire        q_out_eff;
    wire        q_out_rtr;
    wire [63:0] q_out_payload;

    can_tx_queue u_queue (
        .clk         (clk),
        .rst_n       (rst_n),
        .push        (queue_push),
        .data_id     (rx_can_id),
        .data_dlc    (rx_can_dlc),
        .data_eff    (rx_can_eff),
        .data_rtr    (rx_can_rtr),
        .data_payload(rx_can_data),
        .pop         (queue_pop),
        .q_id        (q_out_id),
        .q_dlc       (q_out_dlc),
        .q_eff       (q_out_eff),
        .q_rtr       (q_out_rtr),
        .q_payload   (q_out_payload),
        .full        (queue_full),
        .empty       (queue_empty),
        .depth       (queue_depth)
    );

    //==========================================================
    // ETH RX IRQ edge detection
    //==========================================================
    reg eth_rx_irq_d;
    wire eth_rx_irq_posedge = eth_rx_irq_i & ~eth_rx_irq_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) eth_rx_irq_d <= 1'b0;
        else        eth_rx_irq_d <= eth_rx_irq_i;
    end

    //==========================================================
    // Validation signals
    //==========================================================
    wire [15:0] rx_ethertype = rx_frame_buf[3][31:16];
    wire [15:0] rx_magic     = {rx_frame_buf[3][15:8], rx_frame_buf[3][7:0]};
    wire  [7:0] rx_version   = rx_frame_buf[4][31:24];

    wire valid_gateway = (rx_ethertype == `ETHERTYPE_GATEWAY) &&
                         (rx_magic == {`BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO}) &&
                         (rx_version == `BRIDGE_VERSION);

    wire valid_tunnel  = (rx_ethertype == `ETHERTYPE_TUNNEL) &&
                         (rx_magic == {`BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO}) &&
                         (rx_version == `BRIDGE_VERSION);

    wire frame_valid = (bridge_mode == `BRIDGE_MODE_GATEWAY) ? valid_gateway :
                       (bridge_mode == `BRIDGE_MODE_TUNNEL)  ? valid_tunnel  :
                       1'b0;

    //==========================================================
    // FSM — Sequential
    //==========================================================
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= `DN_IDLE;
            word_cnt       <= 5'd0;
            byte_cnt       <= 4'd0;
            bd_cnt         <= 2'd0;
            rx_bd_status_reg <= 32'd0;
            rx_bd_ptr_reg  <= 32'd0;
            rx_can_id      <= 29'd0;
            rx_can_dlc     <= 4'd0;
            rx_can_eff     <= 1'b0;
            rx_can_rtr     <= 1'b0;
            rx_can_data    <= 64'd0;
            queue_push     <= 1'b0;
            queue_pop      <= 1'b0;
            can_wb_req     <= 1'b0;
            can_wb_cyc     <= 1'b0;
            can_wb_stb     <= 1'b0;
            can_wb_we      <= 1'b0;
            can_wb_adr     <= 32'd0;
            can_wb_dat_o   <= 32'd0;
            eth_wb_req     <= 1'b0;
            eth_wb_cyc     <= 1'b0;
            eth_wb_stb     <= 1'b0;
            eth_wb_we      <= 1'b0;
            eth_wb_sel     <= 4'h0;
            eth_wb_adr     <= 32'd0;
            eth_wb_dat_o   <= 32'd0;
            cnt_eth_rx_inc <= 1'b0;
            cnt_can_tx_inc <= 1'b0;
            cnt_errors_inc <= 1'b0;
            for (j = 0; j < `FRAME_WORDS; j = j + 1)
                rx_frame_buf[j] <= 32'd0;
        end else begin
            // Clear single-cycle pulses
            cnt_eth_rx_inc <= 1'b0;
            cnt_can_tx_inc <= 1'b0;
            cnt_errors_inc <= 1'b0;
            queue_push     <= 1'b0;
            queue_pop      <= 1'b0;

            case (state)
                //----------------------------------------------
                // IDLE: Wait for ETH RX interrupt
                //----------------------------------------------
                `DN_IDLE: begin
                    can_wb_cyc <= 1'b0;
                    can_wb_stb <= 1'b0;
                    eth_wb_cyc <= 1'b0;
                    eth_wb_stb <= 1'b0;
                    if (bridge_en && eth_rx_irq_posedge) begin
                        state      <= `DN_READ_BD;
                        bd_cnt     <= 2'd0;
                        eth_wb_req <= 1'b1;
                    end
                end

                //----------------------------------------------
                // READ_BD: Read RX buffer descriptor (2 reads)
                //----------------------------------------------
                `DN_READ_BD: begin
                    if (eth_wb_gnt) begin
                        eth_wb_cyc <= 1'b1;
                        eth_wb_we  <= 1'b0;
                        eth_wb_sel <= 4'hF;

                        if (eth_wb_ack) begin
                            eth_wb_stb <= 1'b0;
                            case (bd_cnt)
                                2'd0: begin
                                    rx_bd_status_reg <= eth_wb_dat_i;
                                    bd_cnt <= 2'd1;
                                end
                                2'd1: begin
                                    rx_bd_ptr_reg <= eth_wb_dat_i;
                                    state    <= `DN_READ_RAM;
                                    word_cnt <= 5'd0;
                                end
                            endcase
                        end else begin
                            eth_wb_stb <= 1'b1;
                            case (bd_cnt)
                                2'd0: eth_wb_adr <= rx_bd_addr;
                                2'd1: eth_wb_adr <= rx_bd_addr + 32'd4;
                            endcase
                        end
                    end
                end

                //----------------------------------------------
                // READ_RAM: Read frame from shared RAM
                //----------------------------------------------
                `DN_READ_RAM: begin
                    eth_wb_cyc <= 1'b1;
                    eth_wb_we  <= 1'b0;
                    eth_wb_sel <= 4'hF;

                    if (eth_wb_ack) begin
                        eth_wb_stb <= 1'b0;
                        rx_frame_buf[word_cnt] <= eth_wb_dat_i;
                        if (word_cnt == 5'd15) begin
                            state      <= `DN_VALIDATE;
                            eth_wb_cyc <= 1'b0;
                            cnt_eth_rx_inc <= 1'b1;
                        end else begin
                            word_cnt <= word_cnt + 1'b1;
                        end
                    end else begin
                        eth_wb_stb <= 1'b1;
                        eth_wb_adr <= rx_bd_ptr_reg + {25'd0, word_cnt, 2'b00};
                    end
                end

                //----------------------------------------------
                // VALIDATE: Check EtherType, magic, version, DLC
                //----------------------------------------------
                `DN_VALIDATE: begin
                    if (!frame_valid) begin
                        // Invalid frame — drop and free BD
                        state <= `DN_FREE_BD;
                        cnt_errors_inc <= 1'b1;
                    end else begin
                        state <= `DN_DECAP;
                    end
                end

                //----------------------------------------------
                // DECAP: Extract CAN frame fields
                //----------------------------------------------
                `DN_DECAP: begin
                    // Word 4: {version, can_id[28:5]}
                    rx_can_id[28:5] <= rx_frame_buf[4][23:0];
                    // Word 5: {can_id[4:0], 3'b0, 4'b0, dlc[3:0], 6'b0, rtr, eff, data[7:0]}
                    rx_can_id[4:0]  <= rx_frame_buf[5][31:27];
                    rx_can_dlc      <= rx_frame_buf[5][19:16];
                    rx_can_rtr      <= rx_frame_buf[5][9];
                    rx_can_eff      <= rx_frame_buf[5][8];

                    if (bridge_mode == `BRIDGE_MODE_TUNNEL) begin
                        // Tunnel: data starts after tunnel header (word 7)
                        rx_can_data[63:56] <= rx_frame_buf[5][7:0];
                        rx_can_data[55:24] <= rx_frame_buf[7];
                        rx_can_data[23:0]  <= rx_frame_buf[8][31:8];
                    end else begin
                        // Gateway: data starts at word 5 byte 0, continues word 6-7
                        rx_can_data[63:56] <= rx_frame_buf[5][7:0];
                        rx_can_data[55:24] <= rx_frame_buf[6];
                        rx_can_data[23:0]  <= rx_frame_buf[7][31:8];
                    end

                    // Validate DLC
                    if (rx_frame_buf[5][19:16] > 4'd8) begin
                        state <= `DN_FREE_BD;
                        cnt_errors_inc <= 1'b1;
                    end else begin
                        state <= `DN_QUEUE_CHK;
                    end
                end

                //----------------------------------------------
                // QUEUE_CHK: Check if CAN TX queue has space
                //----------------------------------------------
                `DN_QUEUE_CHK: begin
                    if (!queue_full) begin
                        state <= `DN_ENQUEUE;
                    end
                    // If full: stay here (backpressure / stall)
                end

                //----------------------------------------------
                // ENQUEUE: Push frame into CAN TX queue
                //----------------------------------------------
                `DN_ENQUEUE: begin
                    queue_push <= 1'b1;
                    state      <= `DN_WRITE_CAN;
                    byte_cnt   <= 4'd0;
                    can_wb_req <= 1'b1;
                    queue_pop  <= 1'b1;  // pop immediately for WRITE_CAN
                end

                //----------------------------------------------
                // WRITE_CAN: Serialize CAN frame to CAN controller
                //----------------------------------------------
                `DN_WRITE_CAN: begin
                    if (can_wb_gnt) begin
                        can_wb_cyc <= 1'b1;
                        can_wb_we  <= 1'b1;

                        if (can_wb_ack) begin
                            can_wb_stb <= 1'b0;
                            if (byte_cnt == 4'd12) begin
                                // All bytes written, now send TX request cmd
                                // Set up for one more write in WAIT_CAN_TX
                                state <= `DN_WAIT_CAN_TX;
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end else begin
                            can_wb_stb <= 1'b1;
                            can_wb_adr <= {24'd0, `CAN_REG_TXBUF_START + byte_cnt};

                            // Serialize frame fields byte-by-byte
                            case (byte_cnt)
                                4'd0:  can_wb_dat_o <= {24'd0, q_out_eff, q_out_rtr, 2'b0, q_out_dlc};
                                4'd1:  can_wb_dat_o <= {24'd0, q_out_id[28:21]};
                                4'd2:  can_wb_dat_o <= {24'd0, q_out_id[20:13]};
                                4'd3:  can_wb_dat_o <= {24'd0, q_out_id[12:5]};
                                4'd4:  can_wb_dat_o <= {24'd0, q_out_id[4:0], 3'b0};
                                4'd5:  can_wb_dat_o <= {24'd0, q_out_payload[63:56]};
                                4'd6:  can_wb_dat_o <= {24'd0, q_out_payload[55:48]};
                                4'd7:  can_wb_dat_o <= {24'd0, q_out_payload[47:40]};
                                4'd8:  can_wb_dat_o <= {24'd0, q_out_payload[39:32]};
                                4'd9:  can_wb_dat_o <= {24'd0, q_out_payload[31:24]};
                                4'd10: can_wb_dat_o <= {24'd0, q_out_payload[23:16]};
                                4'd11: can_wb_dat_o <= {24'd0, q_out_payload[15:8]};
                                4'd12: can_wb_dat_o <= {24'd0, q_out_payload[7:0]};
                            endcase
                        end
                    end
                end

                //----------------------------------------------
                // WAIT_CAN_TX: Wait for CAN TX complete
                //----------------------------------------------
                `DN_WAIT_CAN_TX: begin
                    // First: send the TX request command write
                    if (can_wb_cyc && !can_wb_stb && !can_wb_ack) begin
                        // Set up the TX request write
                        can_wb_stb  <= 1'b1;
                        can_wb_adr  <= {24'd0, `CAN_REG_CMD};
                        can_wb_dat_o <= {24'd0, `CAN_CMD_TX_REQ};
                    end else if (can_wb_ack) begin
                        can_wb_cyc <= 1'b0;
                        can_wb_stb <= 1'b0;
                        can_wb_req <= 1'b0;
                    end

                    // Then wait for CAN TX complete interrupt
                    if (!can_wb_cyc && can_tx_irq_i) begin
                        state <= `DN_FREE_BD;
                        cnt_can_tx_inc <= 1'b1;
                        eth_wb_req <= 1'b1;
                    end
                end

                //----------------------------------------------
                // FREE_BD: Mark RX BD as empty
                //----------------------------------------------
                `DN_FREE_BD: begin
                    if (eth_wb_gnt) begin
                        eth_wb_cyc  <= 1'b1;
                        eth_wb_stb  <= 1'b1;
                        eth_wb_we   <= 1'b1;
                        eth_wb_sel  <= 4'hF;
                        eth_wb_adr  <= rx_bd_addr;
                        // Write BD status: clear all status, set EMPTY
                        eth_wb_dat_o <= {rx_bd_status_reg[31:16], 16'h8000};

                        if (eth_wb_ack) begin
                            state      <= `DN_IDLE;
                            eth_wb_cyc <= 1'b0;
                            eth_wb_stb <= 1'b0;
                            eth_wb_req <= 1'b0;
                        end
                    end
                end

                // coverage off
                default: state <= `DN_IDLE;
                // coverage on
            endcase
        end
    end

endmodule
