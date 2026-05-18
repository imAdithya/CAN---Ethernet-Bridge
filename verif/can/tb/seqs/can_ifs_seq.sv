// PROT-08: Interframe Space (IFS) Sequence
class can_ifs_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_ifs_seq)

  function new(string name = "can_ifs_seq");
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

  task wait_tx_complete();
    logic [7:0] status = 8'h00; int timeout = 1000;
    while ((status & 8'h08) == 8'h00) begin
      #5000; wb_read(8'h02, status); timeout--;
      if (timeout == 0) begin `uvm_error("TX_TIMEOUT", "Timeout!") return; end
    end
  endtask

  virtual task body();
    `uvm_info(get_name(), "=== PROT-08: IFS TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    wb_write(8'h00, 8'h04); // Operating + Self-Test
    #10000;

    // Transmit frame 1
    wb_write(8'h10, 8'h01); // SFF, DLC=1
    wb_write(8'h11, 8'h11); wb_write(8'h12, 8'h20); // ID=0x111
    wb_write(8'h13, 8'hAA);
    wb_write(8'h01, 8'h10); // Self-TX
    
    // Immediately request another transmission to verify IFS is respected
    // The BTL will hold off transmission until IFS completes
    #5000; // Small delay
    wb_write(8'h01, 8'h10); // Request TX again
    
    wait_tx_complete();
    // Wait for the second one as well
    wait_tx_complete();

    `uvm_info(get_name(), "=== PROT-08: IFS TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
