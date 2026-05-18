// ERR-08: Stuff Error Sequence
class can_stuff_error_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_stuff_error_seq)

  function new(string name = "can_stuff_error_seq");
    super.new(name);
  endfunction

  task wb_write(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = addr; req.we = 1'b1; req.data = data; req.sel = 4'h1; finish_item(req);
  endtask

  task wb_read(bit [7:0] addr, output logic [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req); req.addr = addr; req.we = 1'b0; req.data = 8'h00; req.sel = 4'h1; finish_item(req);
    data = req.data;
  endtask

  virtual task body();
    logic [7:0] rec, ecc_val;
    `uvm_info(get_name(), "=== ERR-08: STUFF ERROR TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    wb_write(8'h00, 8'h04); // Operating + Self-Test
    #10000;

    wb_read(8'h0F, rec);
    `uvm_info(get_name(), $sformatf("Initial REC = %0d", rec), UVM_LOW)

    // Transmit
    wb_write(8'h10, 8'h01); 
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40);
    wb_write(8'h13, 8'h11);
    wb_write(8'h01, 8'h10); // Self-TX

    #30000; // Wait for TX

    wb_read(8'h0F, rec);
    `uvm_info(get_name(), $sformatf("Post-TX REC = %0d", rec), UVM_LOW)
    
    wb_read(8'h0C, ecc_val);
    `uvm_info(get_name(), $sformatf("Post-TX ECC = 0x%0h", ecc_val), UVM_LOW)

    `uvm_info(get_name(), "=== ERR-08: STUFF ERROR TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
