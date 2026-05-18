// TX-01: Standard Frame Format (SFF) Transmission Sequence
// Configures DUT in PeliCAN mode, transmits standard CAN frames, and verifies
// correct framing on tx_o via the CAN bus monitor.
//
// Coverage targets:
//   - Standard ID range (0x000 to 0x7FF)
//   - SOF, Control, and CRC field verification for SFF
//
// This is a Wishbone-side sequence that programs the SJA1000 TX registers.
// The CAN bus monitor independently captures and verifies the frame on tx_o.

class can_tx_sff_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_sff_seq)

  // Number of frames to transmit (covers ID range)
  int num_frames = 8;

  function new(string name = "can_tx_sff_seq");
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
        `uvm_warning("TX_SFF", $sformatf("Bus-Off detected! Status=0x%0h", status))
    end
  endtask

  // Transmit one standard frame with given ID, DLC, and data
  task transmit_sff(bit [10:0] can_id, bit [3:0] dlc, bit [7:0] payload[]);
    bit [7:0] id1, id2;
    bit [7:0] frame_info;

    // SJA1000 PeliCAN TX Buffer Layout for SFF:
    //   0x10: Frame Info    [7]=FF(0=SFF), [6]=RTR(0), [3:0]=DLC
    //   0x11: ID byte 1     ID[10:3]
    //   0x12: ID byte 2     ID[2:0] in bits [7:5]
    //   0x13-0x1A: Data 0-7

    frame_info = {1'b0, 1'b0, 2'b00, dlc};  // SFF, no RTR
    id1 = can_id[10:3];
    id2 = {can_id[2:0], 5'b00000};

    `uvm_info("TX_SFF", $sformatf("Loading TX: ID=0x%03h DLC=%0d Data=[0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h 0x%02h]", 
      can_id, dlc, 
      (payload.size > 0) ? payload[0] : 8'h0, (payload.size > 1) ? payload[1] : 8'h0,
      (payload.size > 2) ? payload[2] : 8'h0, (payload.size > 3) ? payload[3] : 8'h0,
      (payload.size > 4) ? payload[4] : 8'h0, (payload.size > 5) ? payload[5] : 8'h0,
      (payload.size > 6) ? payload[6] : 8'h0, (payload.size > 7) ? payload[7] : 8'h0), UVM_LOW)

    // Write TX buffer
    wb_write(8'h10, frame_info);
    wb_write(8'h11, id1);
    wb_write(8'h12, id2);

    // Write data bytes
    for (int i = 0; i < dlc && i < 8; i++) begin
      wb_write(8'h13 + i, payload[i]);
    end

    // Issue Self-TX Request (Command Reg bit 4 = Self Reception Request)
    `uvm_info("TX_SFF", "Issuing Self-TX command (CMR=0x10)...", UVM_MEDIUM)
    wb_write(8'h01, 8'h10);

    // Wait for transmission complete
    wait_tx_complete();
    `uvm_info("TX_SFF", $sformatf("TX complete: ID=0x%03h", can_id), UVM_LOW)
  endtask

  virtual task body();
    logic [7:0] read_val;

    `uvm_info(get_name(), "=== TX-01: STANDARD FRAME FORMAT (SFF) TEST START ===", UVM_LOW)

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
    // BTR0 = 0x00: BRP=0 (tq = 2 clk), SJW=0
    // BTR1 = 0x25: TSEG1=5 (6 tq), TSEG2=2 (3 tq) → 10 tq/bit = 20 clks/bit
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
    // Phase 2: Transmit Standard Frames
    // ===================================================
    `uvm_info(get_name(), "Phase 2: Transmitting Standard CAN Frames...", UVM_LOW)

    // --- Frame 1: Minimum ID = 0x000, DLC=1 ---
    begin
      bit [7:0] d1[] = '{8'hAA};
      transmit_sff(11'h000, 4'd1, d1);
      #2000;
    end

    // --- Frame 2: Maximum ID = 0x7FF, DLC=8 ---
    begin
      bit [7:0] d2[] = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88};
      transmit_sff(11'h7FF, 4'd8, d2);
      #2000;
    end

    // --- Frame 3: Mid ID = 0x123, DLC=4 ---
    begin
      bit [7:0] d3[] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF};
      transmit_sff(11'h123, 4'd4, d3);
      #2000;
    end

    // --- Frame 4: ID = 0x555 (alternating bits), DLC=2 ---
    begin
      bit [7:0] d4[] = '{8'hCA, 8'hFE};
      transmit_sff(11'h555, 4'd2, d4);
      #2000;
    end

    // --- Frame 5: ID = 0x2AA (alternating bits inverted), DLC=0 (no data) ---
    begin
      bit [7:0] d5[];
      d5 = new[0];
      transmit_sff(11'h2AA, 4'd0, d5);
      #2000;
    end

    // --- Frame 6: ID = 0x001 (low range), DLC=3 ---
    begin
      bit [7:0] d6[] = '{8'h01, 8'h02, 8'h03};
      transmit_sff(11'h001, 4'd3, d6);
      #2000;
    end

    // --- Frame 7: ID = 0x7FE (near max), DLC=6 ---
    begin
      bit [7:0] d7[] = '{8'hA1, 8'hB2, 8'hC3, 8'hD4, 8'hE5, 8'hF6};
      transmit_sff(11'h7FE, 4'd6, d7);
      #2000;
    end

    // --- Frame 8: ID = 0x400 (MSB only), DLC=5 ---
    begin
      bit [7:0] d8[] = '{8'h10, 8'h20, 8'h30, 8'h40, 8'h50};
      transmit_sff(11'h400, 4'd5, d8);
      #2000;
    end

    // ===================================================
    // Phase 3: Verification Summary
    // ===================================================
    `uvm_info(get_name(), "Phase 3: All SFF transmissions complete.", UVM_LOW)
    `uvm_info(get_name(), "Check CAN bus monitor log for SOF/Control/CRC field verification.", UVM_LOW)
    `uvm_info(get_name(), "=== TX-01: STANDARD FRAME FORMAT (SFF) TEST COMPLETE ===", UVM_LOW)

  endtask
endclass
