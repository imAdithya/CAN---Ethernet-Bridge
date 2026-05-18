// ERR-05: Acknowledgement Error Sequence
class can_ack_error_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_ack_error_seq)

  function new(string name = "can_ack_error_seq");
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
    logic [7:0] tec, ecc_val;

    `uvm_info(get_name(), "=== ERR-05: ACK ERROR TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    
    // Enter NORMAL operating mode to trigger ACK errors (no other nodes on bus)
    wb_write(8'h00, 8'h00); 
    #10000;

    wb_read(8'h0E, tec);
    `uvm_info(get_name(), $sformatf("Initial TEC = %0d", tec), UVM_LOW)

    // Clear ECC
    wb_read(8'h0C, ecc_val);

    // Transmit
    wb_write(8'h10, 8'h01); 
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40);
    wb_write(8'h13, 8'h11);
    wb_write(8'h01, 8'h01); // Normal TX

    #25000; // Wait for frame to finish and error to be processed

    wb_read(8'h0E, tec);
    `uvm_info(get_name(), $sformatf("TEC after missing ACK = %0d", tec), UVM_LOW)
    
    wb_read(8'h0C, ecc_val);
    `uvm_info(get_name(), $sformatf("ECC after missing ACK = 0x%0h", ecc_val), UVM_LOW)

    wb_write(8'h01, 8'h02); // Abort TX
    #10000;

    `uvm_info(get_name(), "=== ERR-05: ACK ERROR TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
