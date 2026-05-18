class wb_can_mode_switch_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(wb_can_mode_switch_seq)

  function new(string name = "wb_can_mode_switch_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans req;
    logic [7:0] read_val;

    `uvm_info(get_name(), "--- REG-05: STARTING MODE SWITCHING ARCHITECTURE TEST ---", UVM_LOW)

    // ==========================================
    // PROOF 1: The Control vs. Mode Register Signature (Address 0x00)
    // ==========================================
    `uvm_info(get_name(), "--- PROOF 1: Control vs. Mode Register Signature ---", UVM_LOW)
    
    // Set Basic Mode (CDR.7 = 0)
    req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h00; finish_item(req);

    // Read 0x00 and verify Bit 5 is 1 (BasicCAN Control Reg)
    start_item(req); req.addr = 8'h00; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if ((read_val & 8'h20) == 8'h00) begin
      `uvm_error("SIG_FAIL", $sformatf("In Basic Mode, Addr 0x00 (Control) Bit 5 should be 1. Got: 0x%0x", read_val))
    end else begin
      `uvm_info(get_name(), $sformatf("Pass: Basic Mode Control Reg signature verified (0x00 = 0x%0x)", read_val), UVM_MEDIUM)
    end

    // Set PeliCAN Mode (CDR.7 = 1)
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; finish_item(req);

    // Read 0x00 and verify Bits 7:5 are 000 (PeliCAN Mode Reg)
    start_item(req); req.addr = 8'h00; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if ((read_val & 8'hE0) !== 8'h00) begin
      `uvm_error("SIG_FAIL", $sformatf("In PeliCAN Mode, Addr 0x00 (Mode) Bits 7:5 should be 0. Got: 0x%0x", read_val))
    end else begin
      `uvm_info(get_name(), $sformatf("Pass: PeliCAN Mode Reg signature verified (0x00 = 0x%0x)", read_val), UVM_MEDIUM)
    end

    // ==========================================
    // PROOF 2: The Address Map "Mirror" Check
    // ==========================================
    `uvm_info(get_name(), "--- PROOF 2: Address Map Mirror Check ---", UVM_LOW)

    // Wait, the test states write a unique value to 0x00. In BasicCAN 0x00 is the Control Register. 
    // The Control Register bits might not hold arbitary unique values. Let's use 0x04 (Acceptance Code 0) 
    // which is a standard R/W register in Reset mode. We'll write to 0x04 and read from 0x24 (0x04 + 0x20)
    
    // Set Basic Mode (CDR.7 = 0) AND Reset Mode (MOD.0 = 1) so 0x04 is writable!
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h00; finish_item(req);
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode
    
    // Write 0xAA to 0x04
    start_item(req); req.addr = 8'h04; req.we = 1'b1; req.data = 8'hAA; finish_item(req);
    
    // Read 0x24 (Mirrored 0x04) in Basic Mode
    start_item(req); req.addr = 8'h24; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'hAA) begin
      `uvm_error("MIRROR_FAIL", $sformatf("In Basic Mode, Addr 0x24 failed to mirror 0x04. Expected: 0xAA, Got: 0x%0x", read_val))
    end else begin
      `uvm_info(get_name(), "Pass: Basic Mode 32-byte Address Mirroring active", UVM_MEDIUM)
    end

    // Transition to PeliCAN Profile
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; finish_item(req);
    // Write to PeliCAN's overlapping 0x04 to something else just in case (e.g. Interrupt Enable)
    // Actually wait, PeliCAN extended register 0x24 is empty/zero. Let's just read it directly.
    start_item(req); req.addr = 8'h24; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val === 8'hAA) begin
     `uvm_error("MIRROR_FAIL", $sformatf("In PeliCAN Mode, Addr 0x24 is unlawfully mirroring Basic 0x04! Got: 0x%0x", read_val))
    end else begin
      `uvm_info(get_name(), $sformatf("Pass: PeliCAN Mode correctly broke the 32-byte alias (0x24 = 0x%0x)", read_val), UVM_MEDIUM)
    end

    // ==========================================
    // PROOF 3: The "FFH" Read-Only Protection
    // ==========================================
    `uvm_info(get_name(), "--- PROOF 3: FFH Read-Only Masking on BTR ---", UVM_LOW)

    // Pre-program BTR to a known good value in PeliCAN + Reset Mode (so it's saved)
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; finish_item(req); // PeliCAN
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode
    start_item(req); req.addr = 8'h06; req.we = 1'b1; req.data = 8'h12; finish_item(req); // BTR0
    
    // Switch to Operating Mode
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h00; finish_item(req); // Operating

    // In PeliCAN Operating Mode, Reading BTR (0x06) should STILL yield the 0x12 programmed timing value!
    start_item(req); req.addr = 8'h06; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'h12) begin
       `uvm_error("FFH_FAIL", $sformatf("In PeliCAN Operating Mode, BTR0 (0x06) corrupts on read. Expected: 0x12, Got: 0x%0x", read_val))
    end else begin
       `uvm_info(get_name(), "Pass: PeliCAN Mode returns accurate BTR timing values during operation", UVM_MEDIUM)
    end

    // CRITICAL FIX: The Clock Divider (0x1F) is ONLY writable in Reset Mode!
    // We must enter Reset Mode first, switch to Basic Mode, and THEN re-enter Operating Mode.
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode
    
    // Switch to Basic Mode (CDR.7 = 0)
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h00; finish_item(req);
    
    // Switch BACK to Operating Mode (MOD.0 = 0) so we can trigger the 0xFF masking
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h00; finish_item(req);

    // In BasicCAN Operating Mode, Reading BTR (0x06) should FORCEFULLY yield 0xFF!
    start_item(req); req.addr = 8'h06; req.we = 1'b0; finish_item(req);
    read_val = req.data;
    if (read_val !== 8'hFF) begin
       `uvm_error("FFH_FAIL", $sformatf("In BasicCAN Operating Mode, BTR0 (0x06) failed FFH masking! Expected: 0xFF, Got: 0x%0x", read_val))
    end else begin
       `uvm_info(get_name(), "Pass: BasicCAN Mode forces 0xFF pad on BTR read during operation", UVM_MEDIUM)
    end

    `uvm_info(get_name(), "--- REG-05: MODE SWITCHING TEST COMPLETE ---", UVM_LOW)
  endtask
endclass
