// TX-09: Burst Transmit Sequence
// For each DLC from 1 to 8, transmit 50 frames with fully randomized payloads.
// Total: 8 x 50 = 400 frames. Scoreboard verifies bit-perfect delivery.

class can_tx_burst_transmit_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_burst_transmit_seq)

  function new(string name = "can_tx_burst_transmit_seq");
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

  // Wait for TX Complete
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
    end while ((status & 8'h08) == 8'h00);
  endtask

  virtual task body();
    bit [7:0] tx_data[8];
    bit [28:0] rand_id_29;
    bit [10:0] rand_id_11;
    bit        is_eff;
    int frame_count = 0;
    string data_str;

    `uvm_info(get_name(), "=== TX-09: BURST TRANSMIT START (400 frames, SFF/EFF randomized) ===", UVM_LOW)

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

    // For each DLC from 1 to 8
    for (int dlc = 1; dlc <= 8; dlc++) begin
      `uvm_info("BURST", $sformatf("--- DLC=%0d: Transmitting 50 random frames (SFF/EFF) ---", dlc), UVM_LOW)

      for (int iter = 0; iter < 50; iter++) begin
        frame_count++;

        // Randomize SFF or EFF
        is_eff = $urandom_range(0, 1);

        // Randomize payload bytes
        for (int b = 0; b < 8; b++) begin
          tx_data[b] = (b < dlc) ? $urandom_range(0, 255) : 8'h00;
        end

        // Build data string for logging
        data_str = "";
        for (int b = 0; b < dlc; b++) begin
          data_str = $sformatf("%s%02h ", data_str, tx_data[b]);
        end

        if (is_eff) begin
          // --- EFF Frame (29-bit ID) ---
          rand_id_29 = $urandom_range(0, (1 << 29) - 1);
          `uvm_info("BURST", $sformatf("Frame #%0d [EFF]: ID=0x%07h DLC=%0d Data=[%s]",
            frame_count, rand_id_29, dlc, data_str), UVM_LOW)

          // Frame Info: FF=1, RTR=0, DLC
          wb_write(8'h10, {1'b1, 1'b0, 2'b00, dlc[3:0]});
          // EFF ID: 4 bytes
          wb_write(8'h11, rand_id_29[28:21]);
          wb_write(8'h12, rand_id_29[20:13]);
          wb_write(8'h13, rand_id_29[12:5]);
          wb_write(8'h14, {rand_id_29[4:0], 3'b000});
          // Data starts at 0x15 for EFF
          for (int b = 0; b < dlc; b++) begin
            wb_write(8'h15 + b, tx_data[b]);
          end
        end else begin
          // --- SFF Frame (11-bit ID) ---
          rand_id_11 = $urandom_range(0, 2047);
          `uvm_info("BURST", $sformatf("Frame #%0d [SFF]: ID=0x%03h DLC=%0d Data=[%s]",
            frame_count, rand_id_11, dlc, data_str), UVM_LOW)

          // Frame Info: FF=0, RTR=0, DLC
          wb_write(8'h10, {1'b0, 1'b0, 2'b00, dlc[3:0]});
          // SFF ID: 2 bytes
          wb_write(8'h11, rand_id_11[10:3]);
          wb_write(8'h12, {rand_id_11[2:0], 5'b00000});
          // Data starts at 0x13 for SFF
          for (int b = 0; b < dlc; b++) begin
            wb_write(8'h13 + b, tx_data[b]);
          end
        end

        // Trigger TX
        wb_write(8'h01, 8'h01);
        wait_tx_complete();
        #2000;
      end
    end

    `uvm_info(get_name(), $sformatf("=== TX-09: BURST TRANSMIT COMPLETE (%0d frames) ===", frame_count), UVM_LOW)
  endtask
endclass
