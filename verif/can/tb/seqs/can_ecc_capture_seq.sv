// ERR-01: Error Code Capture (ECC) Reporting Sequence
class can_ecc_capture_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_ecc_capture_seq)

  function new(string name = "can_ecc_capture_seq");
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
    logic [7:0] ecc_val;
    logic [7:0] status;
    int timeout;

    `uvm_info(get_name(), "=== ERR-01: ECC CAPTURE TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    // Enter NORMAL operating mode. Without an active receiver on the bus,
    // this will cause an ACK Error.
    wb_write(8'h00, 8'h00); 
    #10000;

    // Clear ECC by reading it
    wb_read(8'h0C, ecc_val);

    // Transmit SFF Frame
    wb_write(8'h10, 8'h01); 
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40);
    wb_write(8'h13, 8'h11);
    wb_write(8'h01, 8'h01); // TX Request (Normal)

    // Wait for error interrupt or some time since it will continuously retransmit and fail
    #50000; 

    // Read ECC
    wb_read(8'h0C, ecc_val);
    `uvm_info(get_name(), $sformatf("Captured ECC = 0x%0h", ecc_val), UVM_LOW)

    // Optional: Abort transmission so we don't spam the bus forever
    wb_write(8'h01, 8'h02); // Abort TX
    #10000;

    `uvm_info(get_name(), "=== ERR-01: ECC CAPTURE TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
