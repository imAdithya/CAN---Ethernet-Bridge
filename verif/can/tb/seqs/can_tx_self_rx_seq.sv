// TX-05: Self-Reception Request (SRR) Sequence
// Configures DUT in PeliCAN mode. Transmits a frame with CMR.4 = 1.
// Verifies that the transmitted frame appears identically in the local RX FIFO.

class can_tx_self_rx_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_self_rx_seq)

  function new(string name = "can_tx_self_rx_seq");
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

  // Helper: Read a register via Wishbone, return data
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

  // Wait for either TX or RX to flag complete
  task wait_rx_complete();
    logic [7:0] status;
    int timeout = 500;
    status = 8'h00;
    // status[0] = Receive Buffer Status (1 = messages available)
    while ((status & 8'h01) == 8'h00) begin
      #5000;  // 5us between polls
      wb_read(8'h02, status);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TX_TIMEOUT", "Self-Reception did not arrive in RX FIFO within timeout!")
        return;
      end
    end
  endtask

  // Transmit a specific DLC length frame with randomized data
  // using Self-Reception Request (CMR.4)
  task test_self_reception();
    bit [10:0] can_id = 11'h2AF;
    bit [3:0]  dlc = 4'h4;
    bit [7:0]  payload[4] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF};
    
    bit [7:0]  tx_frame_info, tx_id1, tx_id2;
    bit [7:0]  rx_val;
    bit [7:0]  rmc;

    `uvm_info("SRR_SEQ", "Starting Self-Reception (CMR.4) test sequence...", UVM_LOW)

    // SJA1000 PeliCAN SFF: 0x10.7 = FF(0), 0x10.6 = RTR(0)
    tx_frame_info = {1'b0, 1'b0, 2'b00, dlc};
    tx_id1 = can_id[10:3];
    tx_id2 = {can_id[2:0], 5'b00000};

    // --- 1. WRITE TO TX BUFFER ---
    wb_write(8'h10, tx_frame_info);
    wb_write(8'h11, tx_id1);
    wb_write(8'h12, tx_id2);
    for (int i = 0; i < dlc; i++) begin
      wb_write(8'h13 + i, payload[i]);
    end

    // --- 2. TRIGGER SELF RECEPTION REQUEST ---
    // CMR (0x01): Bit 4 = Self Reception Request
    wb_write(8'h01, 8'h10); 

    // --- 3. WAIT FOR BUFFER ---
    wait_rx_complete();

    // --- 4. VERIFY RX FIFO COUNTER ---
    wb_read(8'h1D, rmc); // RX Message Counter
    if (rmc != 8'h01) begin
      `uvm_error("SRR_SEQ", $sformatf("RX Message Counter (RMC) expected 1, but got %0d", rmc))
    end else begin
      `uvm_info("SRR_SEQ", $sformatf("RX Message Counter successfully incremented to: RMC=%0d", rmc), UVM_LOW)
    end

    // --- 5. VERIFY RX FIFO DATA ---
    wb_read(8'h10, rx_val);
    if (rx_val !== tx_frame_info) `uvm_error("SRR_SEQ", $sformatf("Frame Info mismatch! Exp: %0h, Obs: %0h", tx_frame_info, rx_val))
    `uvm_info("SRR_SEQ", $sformatf("Read RX FIFO Frame Info : 0x%02h", rx_val), UVM_LOW)
    
    wb_read(8'h11, rx_val);
    if (rx_val !== tx_id1) `uvm_error("SRR_SEQ", $sformatf("ID1 mismatch! Exp: %0h, Obs: %0h", tx_id1, rx_val))
    `uvm_info("SRR_SEQ", $sformatf("Read RX FIFO ID1        : 0x%02h", rx_val), UVM_LOW)
    
    wb_read(8'h12, rx_val);
    if (rx_val !== tx_id2) `uvm_error("SRR_SEQ", $sformatf("ID2 mismatch! Exp: %0h, Obs: %0h", tx_id2, rx_val))
    `uvm_info("SRR_SEQ", $sformatf("Read RX FIFO ID2        : 0x%02h", rx_val), UVM_LOW)

    for (int i = 0; i < dlc; i++) begin
      wb_read(8'h13 + i, rx_val);
      if (rx_val !== payload[i]) begin
         `uvm_error("SRR_SEQ", $sformatf("Payload[%0d] mismatch! Exp: %0h, Obs: %0h", i, payload[i], rx_val))
      end else begin
         `uvm_info("SRR_SEQ", $sformatf("Read RX FIFO Payload[%0d]: 0x%02h", i, rx_val), UVM_LOW)
      end
    end

    `uvm_info("SRR_SEQ", "Self-Reception Data perfectly matches TX frame!", UVM_LOW)

    // --- 6. RELEASE RECEIVE BUFFER ---
    // CMR (0x01): Bit 2 = Release Receive Buffer
    wb_write(8'h01, 8'h04); 
    
    // Verify RMC goes back to 0
    #1000;
    wb_read(8'h1D, rmc);
    if (rmc !== 8'h00) begin
       `uvm_error("SRR_SEQ", "Failed to Release Receive Buffer correctly!")
    end

  endtask

  virtual task body();
    `uvm_info(get_name(), "=== TX-05: SELF-RECEPTION REQUEST (SRR) START ===", UVM_LOW)

    // Phase 1: Configure PeliCAN Mode
    wb_write(8'h00, 8'h01);
    wb_write(8'h1F, 8'h80);
    wb_write(8'h14, 8'hFF);  
    wb_write(8'h15, 8'hFF);  
    wb_write(8'h16, 8'hFF);  
    wb_write(8'h17, 8'hFF);  
    wb_write(8'h06, 8'h00);  
    wb_write(8'h07, 8'h25);  
    wb_write(8'h00, 8'h04); // Exit reset mode (Dual Filter Mode default)
    #1000;

    test_self_reception();

    `uvm_info(get_name(), "=== TX-05: SELF-RECEPTION REQUEST (SRR) COMPLETE ===", UVM_LOW)
  endtask
endclass
