// PROT-03: Hard Synchronization Sequence
class can_hard_sync_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_hard_sync_seq)

  function new(string name = "can_hard_sync_seq");
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

  task transmit_sff(bit [10:0] can_id, bit [3:0] dlc, bit [7:0] payload[]);
    wb_write(8'h10, {1'b0, 1'b0, 2'b00, dlc});
    wb_write(8'h11, can_id[10:3]);
    wb_write(8'h12, {can_id[2:0], 5'b00000});
    for (int i = 0; i < dlc && i < 8; i++) wb_write(8'h13 + i, payload[i]);
    wb_write(8'h01, 8'h10); // Self-TX
    wait_tx_complete();
  endtask

  virtual task body();
    `uvm_info(get_name(), "=== PROT-03: HARD SYNC TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25);
    wb_write(8'h00, 8'h04); // Operating + Self-Test
    #10000;

    // Transmit a frame. During Self-Test mode, the DUT receives its own TX, 
    // generating an internal SOF that exercises the hard synchronization logic.
    transmit_sff(11'h123, 4'd2, '{8'hAA, 8'h55});
    #10000;

    `uvm_info(get_name(), "=== PROT-03: HARD SYNC TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
