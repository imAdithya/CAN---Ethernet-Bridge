class wb_can_fifo_addr_map_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(wb_can_fifo_addr_map_seq)

  function new(string name = "wb_can_fifo_addr_map_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans req;
    logic [7:0] target_addrs[] = '{
      8'h10, // Acceptance Code 0 / TX Data 1
      8'h11, // Acceptance Code 1 / TX Data 2
      8'h12, // Acceptance Code 2 / TX Data 3
      8'h13, // Acceptance Code 3 / TX Data 4
      8'h14, // Acceptance Mask 0 / TX Data 5
      8'h15, // Acceptance Mask 1 / TX Data 6
      8'h16, // Acceptance Mask 2 / TX Data 7
      8'h17, // Acceptance Mask 3 / TX Data 8
      8'h18, // TX Data 9
      8'h19, // TX Data 10
      8'h1A, // TX Data 11
      8'h1B, // TX Data 12
      8'h1C  // TX Data 13
    };

    logic [7:0] read_val;

    `uvm_info(get_name(), "--- REG-06: STARTING ADDRESS ALIASING / BANKING TEST ---", UVM_LOW)

    // Phase 0: Enter PeliCAN Mode + Reset Mode (MOD.0 = 1)
    `uvm_info(get_name(), "Phase 0: Putting CAN into Reset/PeliCAN mode...", UVM_LOW)
    req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; finish_item(req); // Extended Mode
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode

    // Phase 1: Reset Mode Masking (MOD.0 = 1)
    `uvm_info(get_name(), "Phase 1: Writing 'Filter' Data (0xAA) to Aliased Addresses (0x10-0x1C) in Reset Mode...", UVM_LOW)
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b1; req.data = 8'hAA; finish_item(req);
    end

    // Phase 2: Operating Mode Switch 
    `uvm_info(get_name(), "Phase 2: Entering Operating Mode (MOD.0 = 0). Physical Architecture Banking active...", UVM_LOW)
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h00; finish_item(req);

    // Read 0x10-0x17. In Operating Mode, these are the TX Buffer. Since we haven't written to the TX buffer,
    // they should technically return 0 (or some random initialized state, but absolutely NOT 0xAA which is safely locked away)
    // Actually wait, per SJA1000 the TX Buffer is WRITE-ONLY! Reading the TX Buffer yields arbitrary data 
    // depending on exactly which physical cell happens to be multiplexed, meaning we can't mathematically assert != 8'hAA cleanly
    // because it might coincidentally be 8'hAA!
    // But we CAN prove the Banking is active by loading unique Payload data into the TX buffer, switching back to Reset Mode,
    // and verifying the Hardware swapped the multiplexer BACK to the 0xAA filters cleanly!

    // Phase 3: Operating Mode TX Load
    `uvm_info(get_name(), "Phase 3: Writing 'Payload' Data (0x55) to TX Buffer window (0x10-0x1C) in Operating Mode...", UVM_LOW)
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b1; req.data = 8'h55; finish_item(req);
    end

    // Phase 4: Reset Mode Bank Restore
    `uvm_info(get_name(), "Phase 4: Restoring Reset Mode. Checking if Hardware automatically banked back to 'Filter' Data...", UVM_LOW)
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode

    // We only read 0x10-0x17 because 0x18-0x1C (the rest of the TX Buffer overlay) does not map to readable registers in Reset mode anyway
    for (int i = 0; i < 8; i++) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b0; finish_item(req);
      read_val = req.data;
      if (read_val !== 8'hAA) begin
        `uvm_error("BANK_FAIL", $sformatf("Banking overlap failed! Filter Address 0x%0x corrupted by TX Payload! Expected 0xAA, Got 0x%0x", target_addrs[i], read_val))
      end else begin
        `uvm_info(get_name(), $sformatf("Pass: Filter Address 0x%0x cleanly banked and protected from TX overlap", target_addrs[i]), UVM_MEDIUM)
      end
    end

    `uvm_info(get_name(), "--- REG-06: ADDRESS ALIASING / BANKING TEST COMPLETE ---", UVM_LOW)
  endtask
endclass
