// ERR-02: Error Counters & Warning Limit Sequence
class can_err_cnt_warning_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_err_cnt_warning_seq)

  function new(string name = "can_err_cnt_warning_seq");
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
    logic [7:0] tec, rec, status, irq;
    int timeout;

    `uvm_info(get_name(), "=== ERR-02: ERR CNT WARNING TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    
    // Set EWL (Error Warning Limit) to 96 (default)
    wb_write(8'h0D, 8'h60); 

    // Enter NORMAL operating mode to trigger ACK errors
    wb_write(8'h00, 8'h00); 
    #10000;

    // Enable Error Warning Interrupt (bit 1)
    wb_write(8'h04, 8'h02);

    // Transmit SFF Frame
    wb_write(8'h10, 8'h01); 
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40);
    wb_write(8'h13, 8'h11);
    wb_write(8'h01, 8'h01); // Normal TX

    // Monitor TEC and Status until Warning limit is reached
    timeout = 1000;
    status = 8'h00;
    while ((status & 8'h40) == 8'h00 && timeout > 0) begin // Status bit 6 = Error Status (Warning)
      #20000;
      wb_read(8'h02, status);
      wb_read(8'h0E, tec);
      `uvm_info(get_name(), $sformatf("Polling... TEC = %0d, Status = 0x%0h", tec, status), UVM_HIGH)
      timeout--;
    end

    if (timeout == 0) begin
      `uvm_error(get_name(), "Timeout waiting for Error Warning Status!")
    end else begin
      `uvm_info(get_name(), "Error Warning Status Reached!", UVM_LOW)
    end

    // Check IRQ
    wb_read(8'h03, irq);
    `uvm_info(get_name(), $sformatf("IRQ Register = 0x%0h", irq), UVM_LOW)

    wb_write(8'h01, 8'h02); // Abort TX
    #10000;

    `uvm_info(get_name(), "=== ERR-02: ERR CNT WARNING TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
