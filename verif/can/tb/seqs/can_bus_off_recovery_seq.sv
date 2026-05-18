// ERR-04: Bus-off Recovery Sequence
class can_bus_off_recovery_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_bus_off_recovery_seq)

  function new(string name = "can_bus_off_recovery_seq");
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
    logic [7:0] tec, status, mod;
    int timeout;

    `uvm_info(get_name(), "=== ERR-04: BUS-OFF RECOVERY TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    
    // Enter NORMAL mode to trigger ACK errors
    wb_write(8'h00, 8'h00); 
    #10000;

    // Transmit to go to Bus-Off
    wb_write(8'h10, 8'h01); 
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40);
    wb_write(8'h13, 8'h11);
    wb_write(8'h01, 8'h01); // Normal TX

    // Monitor for Bus-Off (Status bit 7)
    timeout = 1000;
    status = 8'h00;
    while ((status & 8'h80) == 8'h00 && timeout > 0) begin
      #20000; wb_read(8'h02, status); timeout--;
    end

    if (timeout == 0) begin
      `uvm_error(get_name(), "Timeout waiting for Bus-Off Status!")
      return;
    end
    `uvm_info(get_name(), "Bus-Off Status Reached!", UVM_LOW)

    // Read TXERR to cover bus_off bin (255)
    wb_read(8'h0F, tec);
    `uvm_info(get_name(), $sformatf("TEC at Bus-Off = %0d (expected >= 255)", tec), UVM_LOW)

    // Initiate Recovery: Clear Reset Request bit in Mode register (which gets set on bus-off)
    // SJA1000 automatically enters reset mode on Bus-off. We clear it to start recovery.
    wb_write(8'h00, 8'h00); 
    
    `uvm_info(get_name(), "Initiated Recovery. Waiting for 128*11 recessive bits...", UVM_LOW)
    
    // Monitor status until Bus-Off bit clears
    timeout = 2000;
    while ((status & 8'h80) != 8'h00 && timeout > 0) begin
      #20000; wb_read(8'h02, status); timeout--;
    end

    if (timeout == 0) `uvm_error(get_name(), "Timeout waiting for Recovery from Bus-Off!")
    else `uvm_info(get_name(), "Recovered from Bus-Off successfully!", UVM_LOW)

    // Verify TEC is 0
    wb_read(8'h0E, tec);
    `uvm_info(get_name(), $sformatf("TEC after recovery = %0d", tec), UVM_LOW)
    if (tec != 0) `uvm_error(get_name(), "TEC is not 0 after recovery!")

    `uvm_info(get_name(), "=== ERR-04: BUS-OFF RECOVERY TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
