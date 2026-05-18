// PROT-04: Resynchronization (SJW) Sequence
class can_resync_sjw_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_resync_sjw_seq)

  function new(string name = "can_resync_sjw_seq");
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

  task config_and_test(bit [1:0] sjw);
    bit [7:0] btr0;
    // BTR0 = SJW in bits 7:6, BRP in bits 5:0
    btr0 = {sjw, 6'h00}; 
    
    `uvm_info(get_name(), $sformatf("Configuring SJW=%0d", sjw+1), UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, btr0); wb_write(8'h07, 8'h25); // BTR1 = TSEG1=5, TSEG2=2
    wb_write(8'h00, 8'h04); // Operating + Self-Test
    #10000;

    // Transmit
    wb_write(8'h10, 8'h02); // SFF, DLC=2
    wb_write(8'h11, 8'h12); wb_write(8'h12, 8'h60); // ID=0x123
    wb_write(8'h13, 8'hAA); wb_write(8'h14, 8'h55);
    wb_write(8'h01, 8'h10); // Self-TX
    wait_tx_complete();
    #5000;
  endtask

  virtual task body();
    `uvm_info(get_name(), "=== PROT-04: RESYNC SJW TEST START ===", UVM_LOW)
    config_and_test(2'b00); // SJW=1
    config_and_test(2'b01); // SJW=2
    config_and_test(2'b10); // SJW=3
    config_and_test(2'b11); // SJW=4
    `uvm_info(get_name(), "=== PROT-04: RESYNC SJW TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
