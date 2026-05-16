//////////////////////////////////////////////////////////////////////
////                                                              ////
////  bridge_upstream.v                                           ////
////                                                              ////
////  Upstream data path: CAN → Ethernet.                         ////
////  8-state FSM: IDLE → READ_CAN → FILTER → ENCAP →            ////
////  WRITE_RAM → PROG_BD → WAIT_TX → RELEASE                    ////
////                                                              ////
////  Supports Gateway (0xCAFE) and Tunnel (0xCABE) modes.        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`include "can_eth_bridge_defines.v"

module bridge_upstream (
    input         clk,
    input         rst_n,

    // Control
    input         bridge_en,
    input   [1:0] bridge_mode,

    // Interrupts
    input         can_irq_i,       // CAN RX interrupt
    input         eth_tx_irq_i,    // ETH TX complete interrupt

    // Configuration (from bridge_regs)
    input  [47:0] dst_mac,
    input  [47:0] src_mac,
    input         filter_en,
    input         filter_mode,
    input  [28:0] filter_table_0,  filter_table_1,  filter_table_2,  filter_table_3,
    input  [28:0] filter_table_4,  filter_table_5,  filter_table_6,  filter_table_7,
    input  [28:0] filter_table_8,  filter_table_9,  filter_table_10, filter_table_11,
    input  [28:0] filter_table_12, filter_table_13, filter_table_14, filter_table_15,
    input  [31:0] tx_bd_addr,
    input  [15:0] tunnel_seq,
    input  [15:0] timestamp,

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
    output reg    cnt_can_rx_inc,
    output reg    cnt_eth_tx_inc,
    output reg    cnt_filtered_inc,
    output reg    cnt_errors_inc,
    output reg    tunnel_seq_inc
);

    //==========================================================
    // FSM State Register
    //==========================================================
    reg [3:0] state, state_next;
    assign busy = (state != `UP_IDLE);

    //==========================================================
    // Internal Registers — CAN Frame Latches
    //==========================================================
    reg  [7:0] frame_info_reg;
    reg [28:0] can_id_reg;
    reg  [3:0] can_dlc_reg;
    reg        can_eff_reg;
    reg        can_rtr_reg;
    reg [63:0] can_data_reg;

    //==========================================================
    // Internal Registers — Counters
    //==========================================================
    reg  [3:0] byte_cnt;
    reg  [4:0] word_cnt;
    reg  [1:0] bd_cnt;

    //==========================================================
    // Internal Registers — Encapsulated Frame
    //==========================================================
    reg [31:0] tx_frame_buf [0:`FRAME_WORDS-1];
    reg [10:0] tx_frame_len;
    reg  [7:0] flags_reg;

    // Number of words to write to RAM
    reg  [4:0] frame_words;

    //==========================================================
    // CAN ID Filter Instance
    //==========================================================
    wire       filter_drop;
    wire       filter_result_valid;
    reg        filter_check;

    can_id_filter u_filter (
        .clk            (clk),
        .rst_n          (rst_n),
        .filter_en      (filter_en),
        .filter_mode    (filter_mode),
        .filter_table_0 (filter_table_0),  .filter_table_1 (filter_table_1),
        .filter_table_2 (filter_table_2),  .filter_table_3 (filter_table_3),
        .filter_table_4 (filter_table_4),  .filter_table_5 (filter_table_5),
        .filter_table_6 (filter_table_6),  .filter_table_7 (filter_table_7),
        .filter_table_8 (filter_table_8),  .filter_table_9 (filter_table_9),
        .filter_table_10(filter_table_10), .filter_table_11(filter_table_11),
        .filter_table_12(filter_table_12), .filter_table_13(filter_table_13),
        .filter_table_14(filter_table_14), .filter_table_15(filter_table_15),
        .can_id         (can_id_reg),
        .check_valid    (filter_check),
        .filter_drop    (filter_drop),
        .result_valid   (filter_result_valid)
    );

    //==========================================================
    // Timestamp counter (prescaled, 20 µs resolution)
    //==========================================================
    // Timestamp is provided as input from top-level

    //==========================================================
    // CAN IRQ edge detection
    //==========================================================
    reg can_irq_d;
    wire can_irq_posedge = can_irq_i & ~can_irq_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) can_irq_d <= 1'b0;
        else        can_irq_d <= can_irq_i;
    end

    //==========================================================
    // FSM — Sequential
    //==========================================================
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= `UP_IDLE;
            byte_cnt       <= 4'd0;
            word_cnt       <= 5'd0;
            bd_cnt         <= 2'd0;
            frame_info_reg <= 8'd0;
            can_id_reg     <= 29'd0;
            can_dlc_reg    <= 4'd0;
            can_eff_reg    <= 1'b0;
            can_rtr_reg    <= 1'b0;
            can_data_reg   <= 64'd0;
            flags_reg      <= 8'd0;
            tx_frame_len   <= 11'd0;
            frame_words    <= 5'd0;
            filter_check   <= 1'b0;
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
            cnt_can_rx_inc   <= 1'b0;
            cnt_eth_tx_inc   <= 1'b0;
            cnt_filtered_inc <= 1'b0;
            cnt_errors_inc   <= 1'b0;
            tunnel_seq_inc   <= 1'b0;
            for (j = 0; j < `FRAME_WORDS; j = j + 1)
                tx_frame_buf[j] <= 32'd0;
        end else begin
            // Default: clear single-cycle pulses
            cnt_can_rx_inc   <= 1'b0;
            cnt_eth_tx_inc   <= 1'b0;
            cnt_filtered_inc <= 1'b0;
            cnt_errors_inc   <= 1'b0;
            tunnel_seq_inc   <= 1'b0;
            filter_check     <= 1'b0;

            case (state)
                //----------------------------------------------
                // IDLE: Wait for CAN RX interrupt
                //----------------------------------------------
                `UP_IDLE: begin
                    can_wb_cyc <= 1'b0;
                    can_wb_stb <= 1'b0;
                    eth_wb_cyc <= 1'b0;
                    eth_wb_stb <= 1'b0;
                    if (bridge_en && can_irq_posedge) begin
                        state    <= `UP_READ_CAN;
                        byte_cnt <= 4'd0;
                        can_wb_req <= 1'b1;
                    end
                end

                //----------------------------------------------
                // READ_CAN: Read 13 bytes from CAN RX buffer
                //----------------------------------------------
                `UP_READ_CAN: begin
                    if (can_wb_gnt) begin
                        can_wb_cyc <= 1'b1;
                        can_wb_we  <= 1'b0;

                        if (can_wb_ack) begin
                            // Deassert stb after ack — Wishbone single-cycle
                            can_wb_stb <= 1'b0;

                            // Demux incoming byte based on byte_cnt
                            case (byte_cnt)
                                4'd0: begin
                                    frame_info_reg <= can_wb_dat_i[7:0];
                                    can_eff_reg    <= can_wb_dat_i[7];
                                    can_rtr_reg    <= can_wb_dat_i[6];
                                    can_dlc_reg    <= can_wb_dat_i[3:0];
                                end
                                4'd1: can_id_reg[28:21] <= can_wb_dat_i[7:0];
                                4'd2: can_id_reg[20:13] <= can_wb_dat_i[7:0];
                                4'd3: can_id_reg[12:5]  <= can_wb_dat_i[7:0];
                                4'd4: can_id_reg[4:0]   <= can_wb_dat_i[7:3];
                                4'd5:  can_data_reg[63:56] <= can_wb_dat_i[7:0];
                                4'd6:  can_data_reg[55:48] <= can_wb_dat_i[7:0];
                                4'd7:  can_data_reg[47:40] <= can_wb_dat_i[7:0];
                                4'd8:  can_data_reg[39:32] <= can_wb_dat_i[7:0];
                                4'd9:  can_data_reg[31:24] <= can_wb_dat_i[7:0];
                                4'd10: can_data_reg[23:16] <= can_wb_dat_i[7:0];
                                4'd11: can_data_reg[15:8]  <= can_wb_dat_i[7:0];
                                4'd12: can_data_reg[7:0]   <= can_wb_dat_i[7:0];
                            endcase

                            if (byte_cnt == 4'd12) begin
                                // All bytes read
                                state      <= `UP_FILTER;
                                can_wb_cyc <= 1'b0;
                                can_wb_req <= 1'b0;
                                cnt_can_rx_inc <= 1'b1;
                                filter_check   <= 1'b1;
                            end else begin
                                byte_cnt <= byte_cnt + 1'b1;
                            end
                        end else begin
                            // Assert stb with current address (only when not ack'd)
                            can_wb_stb <= 1'b1;
                            can_wb_adr <= {24'd0, `CAN_REG_TXBUF_START + byte_cnt};
                        end
                    end
                end

                //----------------------------------------------
                // FILTER: Wait for filter result (1 cycle)
                //----------------------------------------------
                `UP_FILTER: begin
                    if (filter_result_valid) begin
                        if (filter_drop) begin
                            // Frame rejected — go back to IDLE
                            state <= `UP_IDLE;
                            cnt_filtered_inc <= 1'b1;
                        end else begin
                            // Frame accepted — proceed to encapsulation
                            state <= `UP_ENCAP;
                            word_cnt <= 5'd0;
                        end
                    end
                end

                //----------------------------------------------
                // ENCAP: Assemble Ethernet frame in tx_frame_buf
                //----------------------------------------------
                `UP_ENCAP: begin
                    flags_reg <= {6'b0, can_rtr_reg, can_eff_reg};

                    // Build 32-bit words
                    // ETH Header (14 bytes = words 0-3 partial)
                    tx_frame_buf[0] <= dst_mac[47:16];
                    tx_frame_buf[1] <= {dst_mac[15:0], src_mac[47:32]};
                    tx_frame_buf[2] <= src_mac[31:0];

                    if (bridge_mode == `BRIDGE_MODE_TUNNEL) begin
                        // Tunnel mode: EtherType 0xCABE
                        tx_frame_buf[3] <= {`ETHERTYPE_TUNNEL, `BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO};
                        // Word 4: Version + CAN ID upper bits
                        tx_frame_buf[4] <= {`BRIDGE_VERSION, can_id_reg[28:5]};
                        // Word 5: CAN ID lower + DLC + flags + first data byte
                        //   {can_id[4:0], 3'b0, 4'b0, dlc[3:0], flags[7:0], data[7:0]} = 32 bits
                        tx_frame_buf[5] <= {can_id_reg[4:0], 3'b0,
                                            4'b0, can_dlc_reg,
                                            6'b0, can_rtr_reg, can_eff_reg,
                                            can_data_reg[63:56]};
                        // Word 6: Tunnel header (seq + timestamp)
                        tx_frame_buf[6] <= {tunnel_seq, timestamp};
                        // Words 7-8: CAN data
                        tx_frame_buf[7] <= can_data_reg[55:24];
                        tx_frame_buf[8] <= {can_data_reg[23:0], 8'h00};
                        // Words 9-15: zero padding
                        tx_frame_buf[9]  <= 32'h0;
                        tx_frame_buf[10] <= 32'h0;
                        tx_frame_buf[11] <= 32'h0;
                        tx_frame_buf[12] <= 32'h0;
                        tx_frame_buf[13] <= 32'h0;
                        tx_frame_buf[14] <= 32'h0;
                        tx_frame_buf[15] <= 32'h0;

                        // Frame length: 14 (ETH) + 9 (bridge) + 4 (tunnel) + DLC
                        // Minimum 46 payload = min 60 total
                        if ((13 + can_dlc_reg) < 46)
                            tx_frame_len <= 11'd60;
                        // coverage off
                        // DLC max is 8, so 13+8=21 < 46 always true
                        else
                            tx_frame_len <= 11'd14 + 11'd13 + {7'd0, can_dlc_reg};
                        // coverage on

                        tunnel_seq_inc <= 1'b1;
                    end else begin
                        // Gateway mode: EtherType 0xCAFE
                        tx_frame_buf[3] <= {`ETHERTYPE_GATEWAY, `BRIDGE_MAGIC_HI, `BRIDGE_MAGIC_LO};
                        tx_frame_buf[4] <= {`BRIDGE_VERSION, can_id_reg[28:5]};
                        tx_frame_buf[5] <= {can_id_reg[4:0], 3'b0,
                                            4'b0, can_dlc_reg,
                                            6'b0, can_rtr_reg, can_eff_reg,
                                            can_data_reg[63:56]};
                        tx_frame_buf[6] <= can_data_reg[55:24];
                        tx_frame_buf[7] <= {can_data_reg[23:0], 8'h00};
                        // Words 8-15: zero padding
                        tx_frame_buf[8]  <= 32'h0;
                        tx_frame_buf[9]  <= 32'h0;
                        tx_frame_buf[10] <= 32'h0;
                        tx_frame_buf[11] <= 32'h0;
                        tx_frame_buf[12] <= 32'h0;
                        tx_frame_buf[13] <= 32'h0;
                        tx_frame_buf[14] <= 32'h0;
                        tx_frame_buf[15] <= 32'h0;

                        // Frame length: 14 (ETH) + 9 (bridge) + DLC
                        if ((9 + can_dlc_reg) < 46)
                            tx_frame_len <= 11'd60;
                        // coverage off
                        // DLC max is 8, so 9+8=17 < 46 always true
                        else
                            tx_frame_len <= 11'd14 + 11'd9 + {7'd0, can_dlc_reg};
                        // coverage on
                    end

                    // Calculate number of 32-bit words (round up)
                    frame_words <= 5'd15;  // always write 15 words (60 bytes)

                    state      <= `UP_WRITE_RAM;
                    word_cnt   <= 5'd0;
                    eth_wb_req <= 1'b1;
                end

                //----------------------------------------------
                // WRITE_RAM: Write frame to shared RAM via Master B
                //----------------------------------------------
                `UP_WRITE_RAM: begin
                    if (eth_wb_gnt) begin
                        eth_wb_cyc  <= 1'b1;
                        eth_wb_we   <= 1'b1;
                        eth_wb_sel  <= 4'hF;

                        if (eth_wb_ack) begin
                            eth_wb_stb <= 1'b0;
                            if (word_cnt == frame_words) begin
                                state    <= `UP_PROG_BD;
                                bd_cnt   <= 2'd0;
                            end else begin
                                word_cnt <= word_cnt + 1'b1;
                            end
                        end else begin
                            eth_wb_stb  <= 1'b1;
                            eth_wb_adr  <= tx_bd_addr + 32'h400 + {25'd0, word_cnt, 2'b00};
                            eth_wb_dat_o <= tx_frame_buf[word_cnt];
                        end
                    end
                end

                //----------------------------------------------
                // PROG_BD: Program TX buffer descriptor
                //----------------------------------------------
                `UP_PROG_BD: begin
                    eth_wb_cyc <= 1'b1;
                    eth_wb_we  <= 1'b1;
                    eth_wb_sel <= 4'hF;

                    if (eth_wb_ack) begin
                        eth_wb_stb <= 1'b0;
                        case (bd_cnt)
                            2'd0: bd_cnt <= 2'd1;
                            2'd1: begin
                                state      <= `UP_WAIT_TX;
                                eth_wb_cyc <= 1'b0;
                                eth_wb_req <= 1'b0;
                            end
                        endcase
                    end else begin
                        eth_wb_stb <= 1'b1;
                        case (bd_cnt)
                            2'd0: begin
                                // Write BD data pointer
                                eth_wb_adr  <= tx_bd_addr + 32'd4;
                                eth_wb_dat_o <= tx_bd_addr + 32'h400;
                            end
                            2'd1: begin
                                // Write BD status: length + CRC + READY
                                eth_wb_adr  <= tx_bd_addr;
                                eth_wb_dat_o <= {tx_frame_len[10:0], 5'b0,
                                                 1'b0,     // WRAP
                                                 1'b0,     // IRQ
                                                 1'b0,     // PAD
                                                 1'b1,     // CRC
                                                 11'b0,
                                                 1'b1};    // READY
                            end
                        endcase
                    end
                end

                //----------------------------------------------
                // WAIT_TX: Wait for ETH MAC TX complete interrupt
                //----------------------------------------------
                `UP_WAIT_TX: begin
                    eth_wb_cyc <= 1'b0;
                    eth_wb_stb <= 1'b0;
                    if (eth_tx_irq_i) begin
                        state      <= `UP_RELEASE;
                        can_wb_req <= 1'b1;
                    end
                end

                //----------------------------------------------
                // RELEASE: Release CAN RX buffer
                //----------------------------------------------
                `UP_RELEASE: begin
                    if (can_wb_gnt) begin
                        can_wb_cyc  <= 1'b1;
                        can_wb_stb  <= 1'b1;
                        can_wb_we   <= 1'b1;
                        can_wb_adr  <= {24'd0, `CAN_REG_CMD};
                        can_wb_dat_o <= {24'd0, `CAN_CMD_REL_BUF};

                        if (can_wb_ack) begin
                            state          <= `UP_IDLE;
                            can_wb_cyc     <= 1'b0;
                            can_wb_stb     <= 1'b0;
                            can_wb_req     <= 1'b0;
                            cnt_eth_tx_inc <= 1'b1;
                        end
                    end
                end

                // coverage off
                default: state <= `UP_IDLE;
                // coverage on
            endcase
        end
    end

endmodule
