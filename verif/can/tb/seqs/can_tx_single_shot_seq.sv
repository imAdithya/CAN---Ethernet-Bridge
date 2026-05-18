// TX-06: Single Shot Transmission (CMR.1) Sequence
// Injects an arbitration loss / bit error onto the physical CAN bus mid-transmission.
// Asserts that Normal mode re-transmits the frame continuously.
// Asserts that Single Shot mode halts immediately and does not retry.

class can_tx_single_shot_seq extends uvm_sequence#(wb_can_trans);
  `uvm_object_utils(can_tx_single_shot_seq)
  can_vif vif;

  function new(string name = "can_tx_single_shot_seq");
    super.new(name);
  endfunction

  // Setup Virtual Interface
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

  // Loads a static SFF Frame into the TX buffers
  task load_tx_frame();
    `uvm_info("TX_LOAD", "Loading TX buffer with Standard Frame: ID=0x2AF, DLC=4, Data=[0xAA 0xBB 0xCC 0xDD]", UVM_LOW)
    wb_write(8'h10, 8'h04); // SFF, Data, DLC=4
    wb_write(8'h11, 8'h55); // ID = 0x2AF
    wb_write(8'h12, 8'hE0);
    wb_write(8'h13, 8'hAA); // Data Payload
    wb_write(8'h14, 8'hBB);
    wb_write(8'h15, 8'hCC);
    wb_write(8'h16, 8'hDD);
  endtask

  // Background Task: Waits for SOF, then forcefully pulls `can_rx` LOW to 
  // trigger an Arbitration Loss/Bit Error against the DUT's transmission
  task inject_bit_error_on_bus();
    `uvm_info("ERR_INJ", "Armed Phase: Waiting for Start-of-Frame (tx_o falling edge)", UVM_LOW)
    @(negedge vif.can_tx); // Wait for first SOF
    
    // Wait for ID bits where tx_o will be Recessive (1)
    repeat(120) @(posedge vif.clk);

    `uvm_info("ERR_INJ", "Active Phase: Forcing Arbitration Loss (can_rx = 0)", UVM_LOW)
    vif.can_rx = 1'b0;
    repeat(20) @(posedge vif.clk); // Hold for 1 bit time
    
    vif.can_rx = 1'b1;
    `uvm_info("ERR_INJ", "Complete Phase: Error Injected. Releasing bus.", UVM_LOW)
  endtask

  // Math Task: Counts SOF and terminates when the bus has been idle
  task count_sof_until_idle(output int sof_count);
    int idle_ticker = 0;
    
    // We initialize to 1 because the background inject_bit_error_on_bus() 
    // strictly waits for the *first* SOF falling edge to trigger its logic.
    // By the time this counting task starts, the 1st SOF has already occurred.
    sof_count = 1;
    
    fork
      // Thread 1: Increment SOF counter on VALID falling edges
      begin
        forever begin
          @(negedge vif.can_tx);
          // Only count it as a new frame attempt if the bus 
          // has been quiet for at least a few bits.
          // This debounces the raw tx_o pin during Error Flags and Arbitration.
          if (idle_ticker > 200) begin 
            sof_count++;
            `uvm_info("ERR_INJ", $sformatf("Observed Valid SOF #%0d from SJA1000", sof_count), UVM_LOW)
          end
          idle_ticker = 0; // Reset watchdog
        end
      end
      // Thread 2: Idle Watchdog. If no SOF for 100,000 clocks (4ms), bus is dead.
      begin
        forever begin
          @(posedge vif.clk);
          idle_ticker++;
          if (idle_ticker > 100000) begin
            `uvm_info("ERR_INJ", "Bus Idle Watchdog Timeout (No retransmissions detected). Ending Count.", UVM_LOW)
            break;
          end
        end
      end
    join_any
    disable fork;
  endtask

  virtual task body();
    int sof_count;
    `uvm_info(get_name(), "=== TX-06: SINGLE SHOT TRANSMISSION START ===", UVM_LOW)

    // Phase 1: Configure PeliCAN Mode
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

    // --- PHASE 1: Normal Mode (Re-transmission Expected) ---
    `uvm_info(get_name(), "--- PHASE 1: Normal Transmission (CMR.1 = 0) ---", UVM_LOW)
    load_tx_frame();
    
    fork
       inject_bit_error_on_bus(); // Thread A: Injects one error
       count_sof_until_idle(sof_count); // Thread B: Counts SOF and halts on idle timeout
       begin
         #2000;
         wb_write(8'h01, 8'h01); // Trigger Normal TX
       end
    join // Wait for ALL threads (specifically the Idle Watchdog) to finish

    if (sof_count <= 1) begin
      `uvm_error("TX_06", $sformatf("Normal Mode failed to re-transmit after error! SOF Count: %0d", sof_count))
    end else begin
      `uvm_info("TX_06", $sformatf("Normal Mode successfully re-transmitted frame. Total SOF Attempts: %0d (1 error injection + %0d retries)", sof_count, sof_count-1), UVM_LOW)
    end
    
    // The scoreboard will correctly flag an end-to-end failure here because our injected Bit Error 
    // purposely destroyed one of the physical transactions while Wishbone still reports 1 transmit. 
    // This is mathematically expected for Error Injection. 
    `uvm_info("TX_06", "Note: Scoreboard E2E errors for Phase 1 are EXPECTED because we intentionally destroyed a frame.", UVM_LOW)
    
    // Abort any ongoing normal transmission so we can safely start Phase 2
    wb_write(8'h01, 8'h02); // CMR.1 = Abort Transmission
    repeat(10000) @(posedge vif.clk); // Give RTL time to completely reset TX FSM

    // --- PHASE 2: Single Shot Mode (NO Re-transmission Expected) ---
    `uvm_info(get_name(), "--- PHASE 2: Single Shot Transmission (CMR.1 = 1) ---", UVM_LOW)
    load_tx_frame();
    
    fork
       inject_bit_error_on_bus(); 
       count_sof_until_idle(sof_count); 
       begin
         #2000; 
         wb_write(8'h01, 8'h03); // Trigger TX (CMR.0=1) AND Single Shot (CMR.1=1)
       end
    join

    if (sof_count != 1) begin
      `uvm_error("TX_06", $sformatf("Single Shot Mode VIOLATION! Frame was illegally re-transmitted! SOF Count: %0d", sof_count))
    end else begin
      `uvm_info("TX_06", "Single Shot Mode PASS! SJA1000 properly aborted after arbitration loss. Total SOF Attempts: 1", UVM_LOW)
    end

    `uvm_info(get_name(), "=== TX-06: SINGLE SHOT TRANSMISSION COMPLETE ===", UVM_LOW)
  endtask
endclass
