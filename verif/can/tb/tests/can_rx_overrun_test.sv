// RX-05: FIFO Full & Overrun
// Note: The SJA1000 reports Data Overrun per-message via the overrun_info FIFO.
// The overrun_status bit only asserts when the message at the read pointer had
// an overrun during its reception. To trigger this, we must fill the FIFO,
// release buffers until we reach the overrun-flagged message slot.
class can_rx_overrun_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_overrun_test)

  function new(string name = "can_rx_overrun_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    int num_frames_sent;
    bit overrun_detected;
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-05: FIFO Full & Overrun Test", UVM_LOW)

    // 1. Configure DUT: PeliCAN, Accept everything
    write_reg(8'h1F, 8'h80);  // CDR.7=1 (PeliCAN mode)
    write_reg(8'h00, 8'h09);  // MOD.0=1 (Reset Mode), MOD.3=1 (Single Filter)
    write_reg(8'h06, 8'h00);  // BTR0
    write_reg(8'h07, 8'h25);  // BTR1
    // AMR0-3 = 0xFF: Accept ALL frames
    write_reg(8'h14, 8'hFF);
    write_reg(8'h15, 8'hFF);
    write_reg(8'h16, 8'hFF);
    write_reg(8'h17, 8'hFF);
    // Enable overrun interrupt (IER.3=1) and receive interrupt (IER.0=1)
    write_reg(8'h04, 8'h09);
    write_reg(8'h00, 8'h08);  // Exit Reset
    #1000ns;

    // 2. Drive many small frames to fill and overflow the 64-byte FIFO
    // SFF DLC=0 frames: Info(1) + ID_hi(1) + ID_lo(1) = 3 bytes each
    // 64 / 3 = 21 frames fill FIFO, frame 22+ will overflow
    num_frames_sent = 25;
    for (int i=0; i<num_frames_sent; i++) begin
      `uvm_info("TEST", $sformatf("Injecting frame %0d (DLC=0)...", i+1), UVM_LOW)
      rx_seq.ide = 0;
      rx_seq.rtr = 0;
      rx_seq.id = 29'h100 + i; rx_seq.dlc = 0;
      rx_seq.start(can_agt.sequencer);
      #200us;
    end

    // 3. Check RMC - should show how many messages fit in FIFO
    begin
      bit [7:0] rmc, status;
      read_reg(8'h1D, rmc);
      read_reg(8'h02, status);
      `uvm_info("TEST", $sformatf("After %0d frames: RMC=%0d, Status=0x%h", num_frames_sent, rmc, status), UVM_LOW)
      
      if (rmc < num_frames_sent)
        `uvm_info("TEST", $sformatf("FIFO accepted %0d of %0d frames (FIFO full confirmed)", rmc, num_frames_sent), UVM_LOW)
      else
        `uvm_warning("TEST", $sformatf("FIFO accepted all %0d frames - FIFO larger than expected!", num_frames_sent))
    end

    // 4. Release all buffered messages, checking for overrun status
    // The SJA1000 overrun flag is per-message in the overrun_info FIFO.
    // It appears in Status Register bit 1 when the current read-pointer
    // message has the overrun flag set.
    overrun_detected = 0;
    begin
      bit [7:0] status, rmc;
      int release_count = 0;
      
      forever begin
        read_reg(8'h02, status);
        
        // Check overrun status
        if (status[1] == 1) begin
          overrun_detected = 1;
          `uvm_info("TEST", $sformatf("Overrun Status (SR.1) detected after releasing %0d messages!", release_count), UVM_LOW)
          break;
        end
        
        // Check if FIFO still has data
        if (status[0] == 0) begin
          `uvm_info("TEST", $sformatf("FIFO empty after releasing %0d messages", release_count), UVM_LOW)
          break;
        end
        
        // Release current buffer
        write_reg(8'h01, 8'h04);
        #500ns;
        release_count++;
        
        if (release_count > 30) begin
          `uvm_warning("TEST", "Safety limit reached")
          break;
        end
      end
    end

    if (overrun_detected)
      `uvm_info("TEST", "PASS: Data Overrun correctly detected!", UVM_LOW)
    else
      `uvm_error("TEST", "FAIL: Data Overrun was not detected after filling FIFO!")

    `uvm_info("TEST", "RX-05: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
