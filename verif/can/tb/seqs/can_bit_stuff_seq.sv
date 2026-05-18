// PROT-02: Bit Stuffing / Destuffing Sequence
class can_bit_stuff_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_bit_stuff_seq)

  function new(string name = "can_bit_stuff_seq");
    super.new(name);
  endfunction

  task wb_write(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr; req.we = 1'b1; req.data = data; req.sel = 4'h1;
    finish_item(req);
  endtask

  task wb_read(bit [7:0] addr, output logic [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr; req.we = 1'b0; req.data = 8'h00; req.sel = 4'h1;
    finish_item(req);
    data = req.data;
  endtask

  task wait_tx_complete();
    logic [7:0] status = 8'h00;
    int timeout = 1000;
    while ((status & 8'h08) == 8'h00) begin
      #5000; wb_read(8'h02, status);
      timeout--;
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
    `uvm_info(get_name(), "=== PROT-02: BIT STUFFING TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    wb_write(8'h00, 8'h04); // Operating + Self-Test
    #10000;

    // Transmit payloads that require heavy bit stuffing (e.g. 0x00, 0xFF)
    transmit_sff(11'h000, 4'd8, '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00});
    #5000;
    transmit_sff(11'h7FF, 4'd8, '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF});
    #5000;
    // Mixed 5-bit sequences
    transmit_sff(11'h555, 4'd4, '{8'hF8, 8'h07, 8'hC0, 8'h3E});
    #5000;

    `uvm_info(get_name(), "=== PROT-02: BIT STUFFING TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
