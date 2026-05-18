// TX-08: Data Field Integrity Sequence
// Transmits frames with "walking 1s" and "walking 0s" patterns
// across all 8 data bytes (64 bits total).
// The scoreboard E2E check verifies bit-perfect delivery.

class can_tx_data_integrity_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_data_integrity_seq)

  function new(string name = "can_tx_data_integrity_seq");
    super.new(name);
  endfunction

  // Helper: Write a register via Wishbone
  task wb_write(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr;
    req.we   = 1'b1;
    req.data = data;
    req.sel  = 4'h1;
    finish_item(req);
  endtask

  // Helper: Read a register via Wishbone
  task wb_read(bit [7:0] addr, output logic [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    start_item(req);
    req.addr = addr;
    req.we   = 1'b0;
    req.data = 8'h00;
    req.sel  = 4'h1;
    finish_item(req);
    data = req.data;
  endtask

  // Wait for TX Complete (Status Register bit 3 = TCS)
  task wait_tx_complete();
    logic [7:0] status;
    int timeout = 500;
    do begin
      #5000;
      wb_read(8'h02, status);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TX_TIMEOUT", "Transmission did not complete within timeout!")
        return;
      end
    end while ((status & 8'h08) == 8'h00); // Wait for TCS=1
  endtask

  // Transmit one frame with the given 8-byte data pattern
  task transmit_pattern(string pattern_name, bit [7:0] data[8]);
    `uvm_info("DATA_INT", $sformatf("Transmitting %s: Data=[%02h %02h %02h %02h %02h %02h %02h %02h]",
      pattern_name, data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]), UVM_LOW)

    // SFF, Data, DLC=8
    wb_write(8'h10, 8'h08);
    // ID = 0x123
    wb_write(8'h11, 8'h24);
    wb_write(8'h12, 8'h60);
    // 8 Data Bytes
    for (int i = 0; i < 8; i++) begin
      wb_write(8'h13 + i, data[i]);
    end

    // Trigger Normal TX
    wb_write(8'h01, 8'h01);
    wait_tx_complete();
    #5000;
  endtask

  virtual task body();
    bit [7:0] pattern[8];
    int bit_pos;

    `uvm_info(get_name(), "=== TX-08: DATA FIELD INTEGRITY START ===", UVM_LOW)

    // Configure PeliCAN Mode
    wb_write(8'h00, 8'h01);
    wb_write(8'h1F, 8'h80);
    wb_write(8'h14, 8'hFF);
    wb_write(8'h15, 8'hFF);
    wb_write(8'h16, 8'hFF);
    wb_write(8'h17, 8'hFF);
    wb_write(8'h06, 8'h00);
    wb_write(8'h07, 8'h25);
    wb_write(8'h00, 8'h04);
    #1000;

    // ============================================================
    // WALKING 1s: Single '1' walks across all 64 bit positions
    // ============================================================
    `uvm_info(get_name(), "--- Walking 1s Pattern (64 iterations) ---", UVM_LOW)
    for (bit_pos = 0; bit_pos < 64; bit_pos++) begin
      // Clear all bytes to 0
      for (int i = 0; i < 8; i++) pattern[i] = 8'h00;
      // Set exactly 1 bit
      pattern[bit_pos / 8] = 8'h01 << (bit_pos % 8);
      transmit_pattern($sformatf("Walking-1 bit[%0d]", bit_pos), pattern);
    end

    // ============================================================
    // WALKING 0s: Single '0' walks across all 64 bit positions
    // ============================================================
    `uvm_info(get_name(), "--- Walking 0s Pattern (64 iterations) ---", UVM_LOW)
    for (bit_pos = 0; bit_pos < 64; bit_pos++) begin
      // Set all bytes to FF
      for (int i = 0; i < 8; i++) pattern[i] = 8'hFF;
      // Clear exactly 1 bit
      pattern[bit_pos / 8] = ~(8'h01 << (bit_pos % 8));
      transmit_pattern($sformatf("Walking-0 bit[%0d]", bit_pos), pattern);
    end

    `uvm_info(get_name(), "=== TX-08: DATA FIELD INTEGRITY COMPLETE (128 frames) ===", UVM_LOW)
  endtask
endclass
