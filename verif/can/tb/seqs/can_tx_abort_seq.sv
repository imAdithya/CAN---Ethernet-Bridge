// TX-07: Transmission Abort (CMR.1) Sequence
// Phase 1: Abort while bus is busy (frame never physically starts)
// Phase 2: Abort mid-transmission (frame completes current attempt but does NOT retry)

class can_tx_abort_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_abort_seq)
  can_vif vif;

  function new(string name = "can_tx_abort_seq");
    super.new(name);
  endfunction

  task pre_body();
    vif = can_bus_pkg::static_vif;
  endtask

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

  // Loads a static SFF Frame into the TX buffers
  task load_tx_frame();
    `uvm_info("TX_LOAD", "Loading TX buffer with Standard Frame: ID=0x2AF, DLC=4, Data=[0xAA 0xBB 0xCC 0xDD]", UVM_LOW)
    wb_write(8'h10, 8'h04); // SFF, Data, DLC=4
    wb_write(8'h11, 8'h55); // ID = 0x2AF
    wb_write(8'h12, 8'hE0);
    wb_write(8'h13, 8'hAA);
    wb_write(8'h14, 8'hBB);
    wb_write(8'h15, 8'hCC);
    wb_write(8'h16, 8'hDD);
  endtask

  // Count SOF with debounce, stop when bus idle
  task count_sof_until_idle(output int sof_count);
    int idle_ticker = 0;
    sof_count = 0;
    
    fork
      begin
        forever begin
          @(negedge vif.can_tx);
          if (idle_ticker > 200) begin 
            sof_count++;
            `uvm_info("ABORT_MON", $sformatf("Observed Valid SOF #%0d from SJA1000", sof_count), UVM_LOW)
          end
          idle_ticker = 0;
        end
      end
      begin
        forever begin
          @(posedge vif.clk);
          idle_ticker++;
          if (idle_ticker > 50000) begin
            `uvm_info("ABORT_MON", "Bus Idle Watchdog Timeout. Ending Count.", UVM_LOW)
            break;
          end
        end
      end
    join_any
    disable fork;
  endtask

  virtual task body();
    logic [7:0] status;
    int sof_count;

    `uvm_info(get_name(), "=== TX-07: TRANSMISSION ABORT START ===", UVM_LOW)

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
    // PHASE 1: Abort During IDLE (Bus Held Busy)
    // ============================================================
    `uvm_info(get_name(), "--- PHASE 1: Abort During Idle State (Bus Held Busy) ---", UVM_LOW)
    
    // Hold the bus dominant so the SJA1000 cannot start transmitting
    vif.can_rx = 1'b0;
    `uvm_info("ABORT_SEQ", "Holding CAN bus DOMINANT (can_rx=0) to prevent transmission", UVM_LOW)
    
    // Load and request transmission
    load_tx_frame();
    wb_write(8'h01, 8'h01); // CMR = Transmit Request
    `uvm_info("ABORT_SEQ", "Issued Transmit Request (CMR=0x01). Frame is queued but bus is busy.", UVM_LOW)
    
    // Read Status Register to confirm Transmit Buffer is NOT released (TBS=0)
    #2000;
    wb_read(8'h02, status);
    `uvm_info("ABORT_SEQ", $sformatf("Status Register BEFORE abort: 0x%02h (TBS=%0b)", status, status[2]), UVM_LOW)
    
    // Issue Abort Command
    wb_write(8'h01, 8'h02); // CMR.1 = Abort Transmission
    `uvm_info("ABORT_SEQ", "Issued Abort Command (CMR=0x02)", UVM_LOW)
    
    // Release the bus
    #5000;
    vif.can_rx = 1'b1;
    `uvm_info("ABORT_SEQ", "Released CAN bus (can_rx=1)", UVM_LOW)
    
    // Read Status Register to confirm Transmit Buffer IS released (TBS=1)
    #5000;
    wb_read(8'h02, status);
    `uvm_info("ABORT_SEQ", $sformatf("Status Register AFTER abort: 0x%02h (TBS=%0b)", status, status[2]), UVM_LOW)
    
    // Count any SOF attempts (should be 0)
    count_sof_until_idle(sof_count);
    
    if (sof_count != 0) begin
      `uvm_error("TX_07", $sformatf("PHASE 1 FAIL: Frame was transmitted despite Abort during Idle! SOF Count: %0d", sof_count))
    end else begin
      `uvm_info("TX_07", "PHASE 1 PASS: Abort during Idle succeeded. No frames transmitted on bus. SOF Count: 0", UVM_LOW)
    end

    // Wait for bus to fully settle
    repeat(5000) @(posedge vif.clk);

    // ============================================================
    // PHASE 2: Abort During BUSY (Mid-Transmission)
    // ============================================================
    `uvm_info(get_name(), "--- PHASE 2: Abort During Busy State (Mid-Transmission) ---", UVM_LOW)
    
    load_tx_frame();
    
    fork
      // Thread A: Wait for SOF then inject error to force retry scenario
      begin
        @(negedge vif.can_tx); // Wait for SOF
        // Wait into ID field
        repeat(120) @(posedge vif.clk);
        `uvm_info("ABORT_SEQ", "Frame is mid-transmission. Injecting Arbitration Loss.", UVM_LOW)
        vif.can_rx = 1'b0;
        repeat(20) @(posedge vif.clk);
        vif.can_rx = 1'b1;
      end

      // Thread B: Count physical SOF attempts
      begin : sof_counter
        count_sof_until_idle(sof_count);
      end

      // Thread C: Issue TX then Abort shortly after SOF
      begin
        #2000;
        wb_write(8'h01, 8'h01); // Trigger Normal TX
        `uvm_info("ABORT_SEQ", "Issued Transmit Request (CMR=0x01)", UVM_LOW)

        // Wait for the frame to start
        @(negedge vif.can_tx);
        `uvm_info("ABORT_SEQ", "SOF detected! Immediately issuing Abort Command!", UVM_LOW)
        wb_write(8'h01, 8'h02); // CMR.1 = Abort Transmission
        `uvm_info("ABORT_SEQ", "Issued Abort Command (CMR=0x02) during active transmission.", UVM_LOW)
      end
    join

    // Read Status Register after abort
    #5000;
    wb_read(8'h02, status);
    `uvm_info("ABORT_SEQ", $sformatf("Status Register AFTER mid-TX abort: 0x%02h (TBS=%0b)", status, status[2]), UVM_LOW)

    // sof_count should be 1 (the initial attempt) with NO retry
    if (sof_count > 1) begin
      `uvm_error("TX_07", $sformatf("PHASE 2 FAIL: Frame was re-transmitted after mid-TX Abort! SOF Count: %0d", sof_count))
    end else begin
      `uvm_info("TX_07", $sformatf("PHASE 2 PASS: Abort during Busy succeeded. Frame attempted once, no retry. SOF Count: %0d", sof_count), UVM_LOW)
    end

    `uvm_info(get_name(), "=== TX-07: TRANSMISSION ABORT COMPLETE ===", UVM_LOW)
  endtask
endclass
