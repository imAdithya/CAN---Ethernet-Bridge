class wb_can_reg_ro_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(wb_can_reg_ro_seq)

  function new(string name = "wb_can_reg_ro_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans req;
    logic [7:0] ro_addrs[] = '{
      8'h02, // Status Register
      8'h03, // Interrupt Register
      8'h0B, // Arbitration Lost Capture
      8'h0C, // Error Code Capture
      8'h0E, // Rx Error Counter
      8'h0F, // Tx Error Counter
      8'h1D  // Rx Message Counter
    };
    string ro_names[] = '{
      "Status Register",
      "Interrupt Register",
      "Arbitration Lost Capture",
      "Error Code Capture",
      "Rx Error Counter",
      "Tx Error Counter",
      "Rx Message Counter"
    };

    logic [7:0] baseline_vals[logic [7:0]];
    logic [7:0] read_val;

    `uvm_info(get_name(), "--- REG-03: STARTING READ-ONLY PROTECTION TEST ---", UVM_LOW)

    // Phase 1: Enter PeliCAN Mode (to access extended RO registers like Arb Lost and Err Capture)
    `uvm_info(get_name(), "Phase 0: Putting CAN into Reset/PeliCAN mode...", UVM_LOW)
    req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = 8'h1F; // Clock Divider
    req.we = 1'b1;
    req.data = 8'h80; // Extended Mode
    finish_item(req);

    start_item(req);
    req.addr = 8'h00; // Mode Register
    req.we = 1'b1;
    req.data = 8'h01; // Reset Mode
    finish_item(req);

    // Phase 1: Baseline Reads
    `uvm_info(get_name(), "Phase 1: Establishing RO Baseline Values", UVM_LOW)
    foreach (ro_addrs[i]) begin
      start_item(req);
      req.addr = ro_addrs[i];
      req.we = 1'b0; // Read
      finish_item(req);
      baseline_vals[ro_addrs[i]] = req.data;
      `uvm_info(get_name(), $sformatf("Baseline: %s (0x%0x) = 0x%0x", ro_names[i], ro_addrs[i], baseline_vals[ro_addrs[i]]), UVM_MEDIUM)
    end

    // Phase 2: Attack (Attempt to overwrite RO registers with 0xFF)
    `uvm_info(get_name(), "Phase 2: Attacking RO Registers with 0xFF", UVM_LOW)
    foreach (ro_addrs[i]) begin
      start_item(req);
      req.addr = ro_addrs[i];
      req.we = 1'b1; // Write
      req.data = 8'hFF;
      finish_item(req);
    end

    // Phase 3: Attack (Attempt to overwrite RO registers with 0x00)
    `uvm_info(get_name(), "Phase 2.5: Attacking RO Registers with 0x00", UVM_LOW)
    foreach (ro_addrs[i]) begin
      start_item(req);
      req.addr = ro_addrs[i];
      req.we = 1'b1; // Write
      req.data = 8'h00;
      finish_item(req);
    end

    // Phase 4: Verification Reads
    `uvm_info(get_name(), "Phase 3: Verifying RO Registers Resisted Corruption", UVM_LOW)
    foreach (ro_addrs[i]) begin
      start_item(req);
      req.addr = ro_addrs[i];
      req.we = 1'b0; // Read
      finish_item(req);
      read_val = req.data;
      
      if (read_val !== baseline_vals[ro_addrs[i]]) begin
        `uvm_error("RO_FAIL", $sformatf("%s (0x%0x) changed! Baseline: 0x%0x, Got: 0x%0x", ro_names[i], ro_addrs[i], baseline_vals[ro_addrs[i]], read_val))
      end else begin
        `uvm_info(get_name(), $sformatf("Pass: %s (0x%0x) securely retained 0x%0x", ro_names[i], ro_addrs[i], read_val), UVM_MEDIUM)
      end
    end

    `uvm_info(get_name(), "--- REG-03: READ-ONLY TEST COMPLETE ---", UVM_LOW)
  endtask
endclass
