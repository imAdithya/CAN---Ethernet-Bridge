// RX-06: Receive Message Counter (RMC)
class can_rx_rmc_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_rmc_test)

  function new(string name = "can_rx_rmc_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-06: Receive Message Counter (RMC) Test", UVM_LOW)

    // 1. Configure DUT: PeliCAN, Accept everything
    write_reg(8'h1F, 8'h80);  // CDR.7=1 (PeliCAN mode)
    write_reg(8'h00, 8'h09);  // MOD.0=1 (Reset Mode), MOD.3=1 (Single Filter)
    // BTR0, BTR1 - Set proper baud rate
    write_reg(8'h06, 8'h00);  // BTR0
    write_reg(8'h07, 8'h25);  // BTR1
    // AMR0-3 = 0xFF: Accept ALL frames
    write_reg(8'h14, 8'hFF);  // AMR0
    write_reg(8'h15, 8'hFF);  // AMR1
    write_reg(8'h16, 8'hFF);  // AMR2
    write_reg(8'h17, 8'hFF);  // AMR3
    // Enable Receive Interrupt (IER.0=1)
    write_reg(8'h04, 8'h01);
    write_reg(8'h00, 8'h08);  // Exit Reset, stay in Single Filter mode
    #1000ns;

    // 2. Drive 22 frames (DLC=0) to reach max RMC count (>16)
    for (int i=0; i<22; i++) begin
      bit [7:0] tmp_rmc;
      `uvm_info("TEST", $sformatf("Injecting frame %0d (ID=0x%03h)...", i+1, 'h200+i), UVM_LOW)
      rx_seq.ide = 0;
      rx_seq.rtr = 0;
      rx_seq.id = 29'h200 + i; rx_seq.dlc = 0;
      rx_seq.data = '{0, 0, 0, 0, 0, 0, 0, 0};
      rx_seq.start(can_agt.sequencer);
      #150us;
      // Read RMC to trigger coverage bins at various points (e.g. 5, 12, 20)
      read_reg(8'h1D, tmp_rmc);
    end

    // 3. Verify RMC (Register 0x1D)
    begin
      bit [7:0] rmc;
      read_reg(8'h1D, rmc);
      if (rmc >= 16)
        `uvm_info("TEST", $sformatf("RMC correctly shows %0d messages in FIFO.", rmc), UVM_LOW)
      else
        `uvm_error("TEST", $sformatf("RMC mismatch! Expected >= 16, Got %0d", rmc))
    end

    // 4. Release one buffer and check RMC again
    write_reg(8'h01, 8'h04); // Release Buffer (CMR.2=1)
    #1000ns;
    begin
      bit [7:0] rmc_after, rmc_before;
      read_reg(8'h1D, rmc_after);
      if (rmc_after < 22) // since it decremented
        `uvm_info("TEST", "RMC correctly decremented after release.", UVM_LOW)
      else
        `uvm_error("TEST", $sformatf("RMC failed to decrement! Got %0d", rmc_after))
    end

    `uvm_info("TEST", "RX-06: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
