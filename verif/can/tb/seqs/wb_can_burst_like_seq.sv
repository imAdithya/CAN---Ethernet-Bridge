class wb_can_burst_like_seq extends uvm_sequence #(wb_can_trans);
  `uvm_object_utils(wb_can_burst_like_seq)

  function new(string name = "wb_can_burst_like_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans tx;

    // --- Back-to-back writes to different CAN registers (in reset mode) ---
    // These are consecutive accesses; the driver handles CDC wait between them.

    // Write 1: Bus Timing 0 register (addr 6) 
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd6;
    tx.data = 8'h45;   // BRP=5, SJW=1
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("WRITE-1: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Write 2: Bus Timing 1 register (addr 7) 
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd7;
    tx.data = 8'h23;   // TSEG1=3, TSEG2=2
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("WRITE-2: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Write 3: Acceptance Code register (addr 4)
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd4;
    tx.data = 8'hAB;
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("WRITE-3: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Write 4: Acceptance Mask register (addr 5)
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd5;
    tx.data = 8'hFF;
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("WRITE-4: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // --- Read back all registers to verify no data corruption ---

    // Read 1: Bus Timing 0
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd6;
    tx.data = 8'h00;
    tx.we   = 1'b0;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("READ-1:  addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Read 2: Bus Timing 1
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd7;
    tx.data = 8'h00;
    tx.we   = 1'b0;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("READ-2:  addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Read 3: Acceptance Code
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd4;
    tx.data = 8'h00;
    tx.we   = 1'b0;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("READ-3:  addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Read 4: Acceptance Mask
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd5;
    tx.data = 8'h00;
    tx.we   = 1'b0;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("READ-4:  addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

  endtask
endclass
