class wb_can_single_access_seq extends uvm_sequence #(wb_can_trans);
  `uvm_object_utils(wb_can_single_access_seq)

  function new(string name = "wb_can_single_access_seq");
    super.new(name);
  endfunction

  virtual task body();
    wb_can_trans tx;

    // --- WB-01: Single Write ---
    // Write to Mode Register (addr 0) to put CAN in reset mode
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd0;    // Mode Register
    tx.data = 8'h01;   // Set reset mode bit
    tx.we   = 1'b1;
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("WRITE: addr=%0h data=%0h", tx.addr, tx.data), UVM_MEDIUM)

    // --- WB-01: Single Read (read back same register) ---
    tx = wb_can_trans::type_id::create("tx");
    start_item(tx);
    tx.addr = 8'd0;    // Mode Register
    tx.data = 8'h00;
    tx.we   = 1'b0;    // Read operation
    tx.sel  = 4'h1;
    finish_item(tx);
    `uvm_info(get_type_name(), $sformatf("READ:  addr=%0h data=%0h", tx.addr, tx.data), UVM_MEDIUM)

  endtask
endclass