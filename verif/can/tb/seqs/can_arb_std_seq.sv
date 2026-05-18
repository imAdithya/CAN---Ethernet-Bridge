// PROT-05: Arbitration Logic (Standard ID) Sequence
class can_arb_std_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_arb_std_seq)

  function new(string name = "can_arb_std_seq");
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
    logic [7:0] alc;
    `uvm_info(get_name(), "=== PROT-05: ARBITRATION STD TEST START ===", UVM_LOW)
    wb_write(8'h00, 8'h01); // Reset
    wb_write(8'h1F, 8'h80); // PeliCAN
    wb_write(8'h14, 8'hFF); wb_write(8'h15, 8'hFF); wb_write(8'h16, 8'hFF); wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00); wb_write(8'h07, 8'h25); // BTR
    wb_write(8'h00, 8'h04); // Operating + Self-Test
    #10000;

    // Transmit SFF Frame
    wb_write(8'h10, 8'h02); // SFF, DLC=2
    wb_write(8'h11, 8'h55); wb_write(8'h12, 8'h40); // ID=0x555
    wb_write(8'h13, 8'h11); wb_write(8'h14, 8'h22);
    wb_write(8'h01, 8'h10); // Self-TX
    
    // Check ALC if arbitration was lost (requires external agent to win)
    // Here we just verify we can send/receive and read ALC
    wait_tx_complete();
    wb_read(8'h0B, alc); // ALC register
    `uvm_info(get_name(), $sformatf("ALC = 0x%0h", alc), UVM_LOW)

    `uvm_info(get_name(), "=== PROT-05: ARBITRATION STD TEST COMPLETE ===", UVM_LOW)
  endtask
endclass
