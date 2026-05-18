class wb_can_reset_stress_seq extends uvm_sequence #(wb_can_trans);
  `uvm_object_utils(wb_can_reset_stress_seq)

  function new(string name = "wb_can_reset_stress_seq");
    super.new(name);
  endfunction

  // This sequence just issues a single write transaction.
  // The test will assert reset mid-cycle externally.
  // After reset recovery, this sequence issues a fresh write + read
  // to verify the bus is functional again.

  virtual task body();
    wb_can_trans tx;

    // Transaction 1: Write that will be interrupted by reset
    `uvm_info(get_type_name(), "Issuing write (will be interrupted by reset)", UVM_LOW)
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd0;
    tx.data = 8'h01;   // Reset mode
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("Pre-reset write completed: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Transaction 2: Post-reset write to verify bus recovery
    `uvm_info(get_type_name(), "Issuing post-reset write to verify bus recovery", UVM_LOW)
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd0;
    tx.data = 8'h01;   // Reset mode again
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("Post-reset write done: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

    // Transaction 3: Post-reset read to confirm data integrity
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd0;
    tx.data = 8'h00;
    tx.we   = 1'b0;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("Post-reset read done: addr=0x%0h data=0x%0h", tx.addr, tx.data), UVM_LOW)

  endtask
endclass
