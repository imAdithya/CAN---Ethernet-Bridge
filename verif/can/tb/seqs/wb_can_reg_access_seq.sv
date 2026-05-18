class wb_can_reg_access_seq extends uvm_sequence #(wb_can_trans);
  `uvm_object_utils(wb_can_reg_access_seq)

  function new(string name = "wb_can_reg_access_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans tx;
    logic [7:0] target_regs[] = '{8'h01, 8'h04, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0D, 8'h0E, 8'h0F, 
                                  8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17};
    logic [7:0] patterns[$];

    // Build the data patterns
    // 1. Walking 1s (0x01, 0x02, 0x04 ... 0x80)
    for (int i = 0; i < 8; i++) begin
      patterns.push_back(8'h01 << i);
    end

    // 2. Walking 0s (0xFE, 0xFD, 0xFB ... 0x7F)
    for (int i = 0; i < 8; i++) begin
      patterns.push_back(~(8'h01 << i));
    end

    // 3. Random patterns
    patterns.push_back(8'hAA);
    patterns.push_back(8'h55);
    patterns.push_back(8'h00);
    patterns.push_back(8'hFF);

    // --- Part 1: Initialization ---
    // Establish PeliCAN mode by writing to Clock Divider (addr 31) MSB
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd31; 
    tx.data = 8'h80;   // Extended mode bit = 1
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), "Entering PeliCAN Mode...", UVM_LOW)

    // Put CAN in reset mode (required to write most config registers)
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd0;    // Mode Register
    tx.data = 8'h01;   // Reset mode bit = 1
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), "Entering Reset Mode...", UVM_LOW)

    // --- Part 2: Register Access Loop ---
    foreach(target_regs[r]) begin
      logic [7:0] current_reg = target_regs[r];
      `uvm_info(get_type_name(), $sformatf("--- TESTING REGISTER: 0x%0h ---", current_reg), UVM_LOW)

      foreach(patterns[p]) begin
        logic [7:0] current_pat = patterns[p];

        // 1. Write Pattern
        tx = wb_can_trans::type_id::create("tx");
        start_item(tx);
        tx.addr = current_reg;
        tx.data = current_pat;
        tx.we   = 1'b1;
        tx.sel  = 4'h1;
        finish_item(tx);
        `uvm_info(get_type_name(), $sformatf("Wrote Pat: 0x%0h to Reg: 0x%0h", current_pat, current_reg), UVM_HIGH)

        // 2. Read Back to Verify
        tx = wb_can_trans::type_id::create("tx");
        start_item(tx);
        tx.addr = current_reg;
        tx.data = 8'h00;
        tx.we   = 1'b0;
        tx.sel  = 4'h1;
        finish_item(tx);
        `uvm_info(get_type_name(), $sformatf("Read Back: 0x%0h from Reg: 0x%0h", tx.data, current_reg), UVM_HIGH)
      end
    end
  

  endtask
endclass
