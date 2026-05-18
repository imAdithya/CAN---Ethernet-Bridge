// TX-02: Extended Frame Format (EFF) Transmission Sequence
// Configures DUT in PeliCAN mode, transmits extended CAN frames, and verifies
// correct framing on tx_o via the CAN bus monitor.
//
// Coverage targets:
//   - Extended ID range (29-bit identifies)
//   - Verify IDE bit is recessive (1)
//
// This is a Wishbone-side sequence that programs the SJA1000 TX registers.
// The CAN bus monitor independently captures and verifies the frame on tx_o.

class can_tx_eff_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_eff_seq)

  // Number of frames to transmit (covers ID range)
  int num_frames = 8;

  function new(string name = "can_tx_eff_seq");
    super.new(name);
  endfunction

  // Helper: Write a register via Wishbone
  task wb_write(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr;
    req.we   = 1'b1;
    req.data = data;
    req.sel  = 4'h1;
    finish_item(req);
  endtask

  // Helper: Read a register via Wishbone, return data
  task wb_read(bit [7:0] addr, output logic [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr;
    req.we   = 1'b0;
    req.data = 8'h00;
    req.sel  = 4'h1;
    finish_item(req);
    data = req.data;
  endtask

  // Helper: Poll status register until TX complete (bit 3 = Transmission Complete)
  task wait_tx_complete();
    logic [7:0] status;
    int timeout = 500;
    status = 8'h00;
    while ((status & 8'h08) == 8'h00) begin
      #5000;  // 5us between polls
      wb_read(8'h02, status);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TX_TIMEOUT", "Transmission did not complete within timeout!")
        return;
      end
      // Check for error states
      if ((status & 8'h80) != 8'h00)
        `uvm_warning("TX_EFF", $sformatf("Bus-Off detected! Status=0x%0h", status))
    end
  endtask

  // Transmit one extended frame with given ID, DLC, and data
  task transmit_eff(bit [28:0] can_id, bit [3:0] dlc, bit [7:0] payload[]);
    bit [7:0] id1, id2, id3, id4;
    bit [7:0] frame_info;

    // SJA1000 PeliCAN TX Buffer Layout for EFF:
    //   0x10: Frame Info    [7]=FF(1=EFF), [6]=RTR(0), [3:0]=DLC
    //   0x11: ID byte 1     ID[28:21]
    //   0x12: ID byte 2     ID[20:13]
    //   0x13: ID byte 3     ID[12:5]
    //   0x14: ID byte 4     ID[4:0] in bits [7:3]
    //   0x15-0x1C: Data 0-7

    frame_info = {1'b1, 1'b0, 2'b00, dlc};  // EFF (FF=1), no RTR
    id1 = can_id[28:21];
    id2 = can_id[20:13];
    id3 = can_id[12:5];
    id4 = {can_id[4:0], 3'b000};

    `uvm_info("TX_EFF", $sformatf("Loading TX: ID=0x%08h DLC=%0d Data=[0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h]", 
      can_id, dlc, 
      (payload.size > 0) ? payload[0] : 8'h0, (payload.size > 1) ? payload[1] : 8'h0,
      (payload.size > 2) ? payload[2] : 8'h0, (payload.size > 3) ? payload[3] : 8'h0,
      (payload.size > 4) ? payload[4] : 8'h0, (payload.size > 5) ? payload[5] : 8'h0,
      (payload.size > 6) ? payload[6] : 8'h0, (payload.size > 7) ? payload[7] : 8'h0), UVM_LOW)

    // Write TX buffer
    wb_write(8'h10, frame_info);
    wb_write(8'h11, id1);
    wb_write(8'h12, id2);
    wb_write(8'h13, id3);
    wb_write(8'h14, id4);

    // Write data bytes
    for (int i = 0; i < dlc && i < 8; i++) begin
      wb_write(8'h15 + i, payload[i]);
    end

    // Issue Self-TX Request (Command Reg bit 4 = Self Reception Request)
    `uvm_info("TX_EFF", "Issuing Self-TX command (CMR=0x10)...", UVM_MEDIUM)
    wb_write(8'h01, 8'h10);

    // Wait for transmission complete
    wait_tx_complete();
    `uvm_info("TX_EFF", $sformatf("TX complete: ID=0x%08h", can_id), UVM_LOW)
  endtask

  virtual task body();
    logic [7:0] read_val;

    `uvm_info(get_name(), "=== TX-02: EXTENDED FRAME FORMAT (EFF) TEST START ===", UVM_LOW)

    // ===================================================
    // Phase 1: DUT Configuration — PeliCAN + Self-Test
    // ===================================================
    `uvm_info(get_name(), "Phase 1: Configuring PeliCAN mode with Self-Test...", UVM_LOW)

    // Enter Reset Mode first (required for configuration)
    wb_write(8'h00, 8'h01);

    // Set PeliCAN Extended Mode (CDR.7 = 1)
    wb_write(8'h1F, 8'h80);

    // Configure Acceptance Filter to accept all frames
    wb_write(8'h14, 8'hFF);  // AMR0
    wb_write(8'h15, 8'hFF);  // AMR1
    wb_write(8'h16, 8'hFF);  // AMR2
    wb_write(8'h17, 8'hFF);  // AMR3

    // Configure Bus Timing
    wb_write(8'h06, 8'h00);  // BTR0
    wb_write(8'h07, 8'h25);  // BTR1

    // Enter Operating Mode with Self-Test (MOD.2=1 for Self-Test, MOD.0=0 for Operating)
    wb_write(8'h00, 8'h04);

    // Verify we're in operating mode
    wb_read(8'h00, read_val);
    `uvm_info(get_name(), $sformatf("Mode Register after config: 0x%0h", read_val), UVM_MEDIUM)

    // Short settle delay
    #1000;

    // ===================================================
    // Phase 2: Transmit Extended Frames
    // ===================================================
    `uvm_info(get_name(), "Phase 2: Transmitting Extended CAN Frames...", UVM_LOW)

    // --- Frame 1: Minimum ID = 0x00000000, DLC=1 ---
    begin
      bit [7:0] d1[] = '{8'hAA};
      transmit_eff(29'h00000000, 4'd1, d1);
      #2000;
    end

    // --- Frame 2: Maximum ID = 0x1FFFFFFF, DLC=8 ---
    begin
      bit [7:0] d2[] = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88};
      transmit_eff(29'h1FFFFFFF, 4'd8, d2);
      #2000;
    end

    // --- Frame 3: Mid ID = 0x12345678, DLC=4 ---
    begin
      bit [7:0] d3[] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF};
      transmit_eff(29'h12345678, 4'd4, d3);
      #2000;
    end

    // --- Frame 4: ID = 0x0AAAAAAA (alternating bits), DLC=2 ---
    begin
      bit [7:0] d4[] = '{8'hCA, 8'hFE};
      transmit_eff(29'h0AAAAAAA, 4'd2, d4);
      #2000;
    end

    // --- Frame 5: ID = 0x15555555 (alternating bits inverted), DLC=0 (no data) ---
    begin
      bit [7:0] d5[];
      d5 = new[0];
      transmit_eff(29'h15555555, 4'd0, d5);
      #2000;
    end

    // --- Frame 6: ID = 0x00000001 (low range), DLC=3 ---
    begin
      bit [7:0] d6[] = '{8'h01, 8'h02, 8'h03};
      transmit_eff(29'h00000001, 4'd3, d6);
      #2000;
    end

    // --- Frame 7: ID = 0x1FFFFFFE (near max), DLC=6 ---
    begin
      bit [7:0] d7[] = '{8'hA1, 8'hB2, 8'hC3, 8'hD4, 8'hE5, 8'hF6};
      transmit_eff(29'h1FFFFFFE, 4'd6, d7);
      #2000;
    end

    // --- Frame 8: ID = 0x10000000 (MSB only), DLC=5 ---
    begin
      bit [7:0] d8[] = '{8'h10, 8'h20, 8'h30, 8'h40, 8'h50};
      transmit_eff(29'h10000000, 4'd5, d8);
      #2000;
    end

    // ===================================================
    // Phase 3: Verification Summary
    // ===================================================
    `uvm_info(get_name(), "Phase 3: All EFF transmissions complete.", UVM_LOW)
    `uvm_info(get_name(), "Check CAN bus monitor log for SOF/Control/CRC field verification.", UVM_LOW)
    `uvm_info(get_name(), "=== TX-02: EXTENDED FRAME FORMAT (EFF) TEST COMPLETE ===", UVM_LOW)

  endtask
endclass
