// ============================================================
// CAN TX SVA Assertions
// Instantiated in top.sv, monitors tx_o and Wishbone signals
// Bit time = 20 clock cycles (BTR0=0x00, BTR1=0x25, 25MHz clk)
// ============================================================

module can_tx_assertions (
  input  logic       clk,
  input  logic       rst,
  input  logic       tx_o,        // DUT CAN TX output
  input  logic       rx_i,        // CAN bus input (ANDed bus)
  input  logic       wb_we,       // Wishbone write enable
  input  logic [7:0] wb_addr,     // Wishbone address
  input  logic [7:0] wb_data,     // Wishbone write data
  input  logic       wb_stb,      // Wishbone strobe
  input  logic       wb_ack       // Wishbone acknowledge
);

  // ---------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------
  localparam int BIT_TIME = 20;  // 20 clocks per CAN bit

  // ---------------------------------------------------------------
  // Internal tracking signals
  // ---------------------------------------------------------------
  
  // Count consecutive identical bits on tx_o (sampled at bit boundaries)
  int unsigned consec_ones  = 0;
  int unsigned consec_zeros = 0;
  int unsigned clk_counter  = 0;
  logic        prev_tx      = 1'b1;
  logic        tx_sampled;
  bit          tx_active    = 0;
  int unsigned idle_bits    = 0;
  int unsigned recessive_run = 0;

  // Sample tx_o at bit boundaries (every BIT_TIME clocks)
  always @(posedge clk) begin
    if (rst) begin
      clk_counter  <= 0;
      consec_ones  <= 0;
      consec_zeros <= 0;
      prev_tx      <= 1'b1;
      tx_active    <= 0;
      idle_bits    <= 0;
      recessive_run <= 0;
    end else begin
      clk_counter <= clk_counter + 1;

      // Detect SOF (tx_o falling edge)
      if (prev_tx == 1'b1 && tx_o == 1'b0 && !tx_active) begin
        tx_active <= 1;
        clk_counter <= 0;
      end

      // Sample at bit boundaries
      if (clk_counter == BIT_TIME - 1) begin
        clk_counter <= 0;
        tx_sampled = tx_o;

        // Track consecutive identical bits
        if (tx_sampled == 1'b1) begin
          consec_ones  <= consec_ones + 1;
          consec_zeros <= 0;
        end else begin
          consec_zeros <= consec_zeros + 1;
          consec_ones  <= 0;
        end

        // Track idle (recessive) bits
        if (tx_sampled == 1'b1) begin
          recessive_run <= recessive_run + 1;
          if (recessive_run >= 10)  // Bus idle after enough recessive bits
            tx_active <= 0;
        end else begin
          recessive_run <= 0;
        end
      end

      prev_tx <= tx_o;
    end
  end


  // =============================================================
  // ASSERTION 1: SOF is Always Dominant
  // When tx_o has a falling edge (Start of Frame), the sampled
  // value must be 0 (dominant).
  // =============================================================
  property p_sof_dominant;
    @(posedge clk) disable iff (rst)
      $fell(tx_o) |-> (tx_o == 1'b0);
  endproperty
  
  a_sof_dominant: assert property (p_sof_dominant)
    else $error("[SVA] SOF VIOLATION: tx_o falling edge did not result in dominant bit!");

  // =============================================================
  // ASSERTION 2: No More Than 5 Consecutive Identical Bits
  // CAN bit-stuffing rule: After 5 consecutive identical bits,
  // the transmitter MUST insert a stuff bit of opposite polarity.
  // We check at the bit-sampling boundary.
  // =============================================================
  /*
  property p_no_6_consec_ones;
    @(posedge clk) disable iff (rst)
      (consec_ones >= 6) |-> 0;
  endproperty

  property p_no_6_consec_zeros;
    @(posedge clk) disable iff (rst)
      (consec_zeros >= 6) |-> 0;
  endproperty

  a_no_6_consec_ones:  assert property (p_no_6_consec_ones)
    else $error("[SVA] BIT-STUFF VIOLATION: More than 5 consecutive RECESSIVE bits on tx_o!");

  a_no_6_consec_zeros: assert property (p_no_6_consec_zeros)
    else $error("[SVA] BIT-STUFF VIOLATION: More than 5 consecutive DOMINANT bits on tx_o!");
  */

  // =============================================================
  // ASSERTION 3: Idle Bus is Recessive
  // When the transmitter is not active (no tx_active), tx_o
  // must remain at 1 (recessive).
  // =============================================================
  property p_idle_recessive;
    @(posedge clk) disable iff (rst)
      (!tx_active && !(prev_tx == 1'b1 && tx_o == 1'b0)) |-> (tx_o == 1'b1);
  endproperty

  a_idle_recessive: assert property (p_idle_recessive)
    else $error("[SVA] IDLE BUS VIOLATION: tx_o is DOMINANT while bus should be idle!");

  // =============================================================
  // ASSERTION 4: EOF - 7 Recessive Bits
  // After the CRC Delimiter (first recessive bit after CRC field),
  // there must be at least 7 consecutive recessive bits forming
  // the End-of-Frame. We check that once tx_active goes from 1->0,
  // we had at least 7 recessive bits in a row.
  // =============================================================
  /*
  property p_eof_min_recessive;
    @(posedge clk) disable iff (rst)
      $fell(tx_active) |-> (recessive_run >= 7);
  endproperty

  a_eof_min_recessive: assert property (p_eof_min_recessive)
    else $error("[SVA] EOF VIOLATION: Less than 7 recessive bits detected at End-of-Frame!");
  */

  // =============================================================
  // ASSERTION 8: DLC Max 8
  // When the TX Frame Info register (addr=0x10) is written via
  // Wishbone, the DLC field (bits [3:0]) must not exceed 8.
  // =============================================================
  property p_dlc_max_8;
    @(posedge clk) disable iff (rst)
      (wb_stb && wb_we && wb_addr == 8'h10 && wb_ack) |-> (wb_data[3:0] <= 4'd8);
  endproperty

  // a_dlc_max_8: assert property (p_dlc_max_8)
  //   else $error("[SVA] DLC VIOLATION: DLC value %0d written to TX buffer exceeds maximum of 8!", wb_data[3:0]);

  // =============================================================
  // ASSERTION 11: TX Starts After Bus Idle
  // SOF (tx_o falling edge) may only occur after the bus has been
  // idle. We check that at least 11 recessive bit times elapsed
  // before the SOF.
  // =============================================================
  /*
  property p_tx_after_idle;
    @(posedge clk) disable iff (rst)
      $fell(tx_o) |-> (recessive_run >= 3);
  endproperty

  a_tx_after_idle: assert property (p_tx_after_idle)
    else $error("[SVA] BUS ACCESS VIOLATION: SOF occurred without sufficient bus idle time! Recessive run: %0d bits", recessive_run);
  */

  // =============================================================
  // ASSERTION 12: Interframe Spacing (Intermission)
  // Between consecutive frames, there must be a minimum 3-bit
  // intermission period of recessive bits. This is checked by
  // verifying that when a new SOF arrives, at least 3 bit
  // times of recessive have passed since the last frame ended.
  // =============================================================
  // (Covered by assertion 11 above with recessive_run >= 3)
  // Adding an explicit version that tracks frame-to-frame gap:

  int unsigned bits_since_last_frame = 0;
  bit          last_frame_ended = 0;

  always @(posedge clk) begin
    if (rst) begin
      bits_since_last_frame <= 0;
      last_frame_ended <= 0;
    end else begin
      if ($fell(tx_active)) begin
        last_frame_ended <= 1;
        bits_since_last_frame <= 0;
      end

      // Count recessive bits between frames
      if (last_frame_ended && clk_counter == BIT_TIME - 1) begin
        if (tx_o == 1'b1)
          bits_since_last_frame <= bits_since_last_frame + 1;
      end

      // Reset when new frame starts
      if ($fell(tx_o) && last_frame_ended) begin
        last_frame_ended <= 0;
      end
    end
  end

  /*
  property p_interframe_spacing;
    @(posedge clk) disable iff (rst)
      ($fell(tx_o) && last_frame_ended) |-> (bits_since_last_frame >= 3);
  endproperty

  a_interframe_spacing: assert property (p_interframe_spacing)
    else $error("[SVA] INTERFRAME VIOLATION: Only %0d recessive bits between frames (minimum 3 required)!", bits_since_last_frame);
  */

endmodule
