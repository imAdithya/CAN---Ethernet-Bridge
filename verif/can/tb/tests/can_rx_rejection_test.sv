// RX-04: Acceptance Rejection
class can_rx_rejection_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_rejection_test)

  function new(string name = "can_rx_rejection_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-04: Acceptance Rejection Test", UVM_LOW)

    // 1. Configure DUT: Single Filter, Match ID 0x123 exactly
    write_reg(8'h1F, 8'h80); // PeliCAN
    write_reg(8'h00, 8'h09); // Reset, Single Filter
    // BTR0, BTR1
    write_reg(8'h06, 8'h00);
    write_reg(8'h07, 8'h25);
    write_reg(8'h10, 8'h24); // ACR0
    write_reg(8'h11, 8'h60); // ACR1
    write_reg(8'h14, 8'h00); // AMR0 (Must match)
    write_reg(8'h15, 8'h00); // AMR1 (Must match)
    
    write_reg(8'h00, 8'h08); // Operating Mode
    #1000ns;

    // 2. Inject Frame with ID 0x124 (Mismatch)
    `uvm_info("TEST", "Injecting Mismatching ID=0x124...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h124; rx_seq.dlc = 4;
    rx_seq.start(can_agt.sequencer);
    #200us;

    // 3. Verify FIFO is still empty
    begin
      bit [7:0] status;
      read_reg(8'h02, status);
      if (status[0] == 0)
        `uvm_info("TEST", "Rejection success: FIFO is empty as expected.", UVM_LOW)
      else
        `uvm_error("TEST", "Rejection failure: FIFO should be empty but it is not!")
    end

    `uvm_info("TEST", "RX-04: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
