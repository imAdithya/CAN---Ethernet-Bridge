// ERR-03: Error State Transitions Sequence
class can_state_transition_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_state_transition_seq)

  function new(string name = "can_state_transition_seq");
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
    logic [7:0] tec, status, irq;
    int timeout;

    `uvm_info(get_name(), "=== ERR-03: STATE TRANSITION TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    
    // Enter NORMAL operating mode to trigger ACK errors
    wb_write(8'h00, 8'h00); 
    #10000;

    // Enable Error Warning and Error Passive Interrupts
    wb_write(8'h04, 8'h22);

    // Transmit SFF Frame
    wb_write(8'h10, 8'h01); 
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40);
    wb_write(8'h13, 8'h11);
    wb_write(8'h01, 8'h01); // Normal TX

    // Monitor for Error Passive (Status bit 5)
    timeout = 1000;
    status = 8'h00;
    while ((status & 8'h20) == 8'h00 && timeout > 0) begin
      #20000;
      wb_read(8'h02, status);
      wb_read(8'h0E, tec);
      `uvm_info(get_name(), $sformatf("Polling Passive... TEC = %0d, Status = 0x%0h", tec, status), UVM_HIGH)
      timeout--;
    end

    if (timeout == 0) `uvm_error(get_name(), "Timeout waiting for Error Passive Status!")
    else `uvm_info(get_name(), "Error Passive Status Reached (TEC > 127)!", UVM_LOW)

    // Monitor for Bus-Off (Status bit 7)
    timeout = 1000;
    while ((status & 8'h80) == 8'h00 && timeout > 0) begin
      #20000;
      wb_read(8'h02, status);
      wb_read(8'h0E, tec);
      `uvm_info(get_name(), $sformatf("Polling Bus-Off... TEC = %0d, Status = 0x%0h", tec, status), UVM_HIGH)
      timeout--;
    end

    if (timeout == 0) `uvm_error(get_name(), "Timeout waiting for Bus-Off Status!")
    else `uvm_info(get_name(), "Bus-Off Status Reached (TEC > 255)!", UVM_LOW)

    `uvm_info(get_name(), "=== ERR-03: STATE TRANSITION TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
