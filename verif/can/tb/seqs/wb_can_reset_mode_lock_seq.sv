class wb_can_reset_mode_lock_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(wb_can_reset_mode_lock_seq)

  function new(string name = "wb_can_reset_mode_lock_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans req;
    logic [7:0] target_addrs[] = '{
      8'h06, // Bus Timing 0
      8'h07, // Bus Timing 1
      8'h10, // Acceptance Code 0
      8'h11, // Acceptance Code 1
      8'h12, // Acceptance Code 2
      8'h13, // Acceptance Code 3
      8'h14, // Acceptance Mask 0
      8'h15, // Acceptance Mask 1
      8'h16, // Acceptance Mask 2
      8'h17  // Acceptance Mask 3
    };
    string target_names[] = '{
      "Bus Timing 0",
      "Bus Timing 1",
      "Acceptance Code 0",
      "Acceptance Code 1",
      "Acceptance Code 2",
      "Acceptance Code 3",
      "Acceptance Mask 0",
      "Acceptance Mask 1",
      "Acceptance Mask 2",
      "Acceptance Mask 3"
    };

    logic [7:0] read_val;

    `uvm_info(get_name(), "--- REG-04: STARTING RESET MODE DEPENDENCY TEST ---", UVM_LOW)

    // Phase 0: Enter PeliCAN Mode + Reset Mode (MOD.0 = 1)
    `uvm_info(get_name(), "Phase 0: Putting CAN into Reset/PeliCAN mode...", UVM_LOW)
    req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; finish_item(req); // Extended Mode
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode

    // Phase 1: Set Baselines (0xAA) while legally in Reset Mode
    `uvm_info(get_name(), "Phase 1: Establishing Baseline Values (0xAA) in Reset Mode", UVM_LOW)
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b1; req.data = 8'hAA; finish_item(req);
    end

    // Enter Operating Mode (MOD.0 = 0)
    `uvm_info(get_name(), "Entering Operating Mode (MOD.0 = 0)...", UVM_LOW)
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h00; finish_item(req);

    // Phase 2: Attack (Attempt to overwrite with 0xFF while running)
    `uvm_info(get_name(), "Phase 2: Attacking Registers with 0xFF in Operating Mode", UVM_LOW)
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b1; req.data = 8'hFF; finish_item(req);
    end

    // Phase 3: Verification
    // CRITICAL: We must re-enter Reset Mode to accurately read ACR/AMR registers back from the OpenCores RTL! 
    // The RTL disconnects their read multiplexers during Operating Mode.
    `uvm_info(get_name(), "Phase 3: Returning to Reset Mode (MOD.0 = 1) to Verify Constraints...", UVM_LOW)
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode

    `uvm_info(get_name(), "Verifying Registers Resisted Operating Mode Corruption...", UVM_LOW)
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b0; finish_item(req);
      read_val = req.data;
      if (read_val !== 8'hAA) begin
        `uvm_error("LOCK_FAIL", $sformatf("%s (0x%0x) corrupted! Expected: 0xAA (locked), Got: 0x%0x", target_names[i], target_addrs[i], read_val))
      end else begin
        `uvm_info(get_name(), $sformatf("Pass: %s (0x%0x) securely locked 0xAA", target_names[i], target_addrs[i]), UVM_MEDIUM)
      end
    end

    // Phase 4: Authorized Overwrite (Return to Reset Mode)
    `uvm_info(get_name(), "Phase 4: Returning to Reset Mode (MOD.0 = 1)...", UVM_LOW)
    start_item(req); req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; finish_item(req); // Reset Mode

    `uvm_info(get_name(), "Attempting Authorized Updates (0x55)...", UVM_LOW)
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b1; req.data = 8'h55; finish_item(req);
    end

    // Verify authorized updates stuck
    foreach (target_addrs[i]) begin
      start_item(req); req.addr = target_addrs[i]; req.we = 1'b0; finish_item(req);
      read_val = req.data;
      if (read_val !== 8'h55) begin
        `uvm_error("AUTH_FAIL", $sformatf("%s (0x%0x) update failed! Expected: 0x55 (authorized), Got: 0x%0x", target_names[i], target_addrs[i], read_val))
      end else begin
        `uvm_info(get_name(), $sformatf("Pass: %s (0x%0x) successfully updated to 0x55", target_names[i], target_addrs[i]), UVM_MEDIUM)
      end
    end

    `uvm_info(get_name(), "--- REG-04: RESET MODE DEPENDENCY TEST COMPLETE ---", UVM_LOW)
  endtask
endclass
