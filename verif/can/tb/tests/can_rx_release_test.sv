// RX-07: Buffer Release
class can_rx_release_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_release_test)

  function new(string name = "can_rx_release_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-07: Buffer Release Test", UVM_LOW)

    // 1. Configure DUT: PeliCAN, Accept everything
    write_reg(8'h1F, 8'h80);  // CDR.7=1 (PeliCAN mode)
    write_reg(8'h00, 8'h09);  // MOD.0=1 (Reset Mode), MOD.3=1 (Single Filter)
    // BTR0, BTR1
    write_reg(8'h06, 8'h00);
    write_reg(8'h07, 8'h25);
    // AMR0-3 = 0xFF: Accept ALL frames
    write_reg(8'h14, 8'hFF);
    write_reg(8'h15, 8'hFF);
    write_reg(8'h16, 8'hFF);
    write_reg(8'h17, 8'hFF);
    write_reg(8'h00, 8'h08);  // Exit Reset, stay in Single Filter mode
    #1000ns;

    // 2. Drive 2 different frames
    `uvm_info("TEST", "Injecting Frame 1 (ID=0x111)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h111; rx_seq.dlc = 4; rx_seq.data = '{8'h11, 8'h22, 8'h33, 8'h44, 0, 0, 0, 0};
    rx_seq.start(can_agt.sequencer);
    #200us;

    `uvm_info("TEST", "Injecting Frame 2 (ID=0x222)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h222; rx_seq.dlc = 2; rx_seq.data = '{8'hAA, 8'hBB, 0, 0, 0, 0, 0, 0};
    rx_seq.start(can_agt.sequencer);
    #200us;

    // 3. Verify Frame 1 is at the top of FIFO
    check_rx_fifo(4, '{8'h11, 8'h22, 8'h33, 8'h44});
    // check_rx_fifo already issues Release Buffer (CMR.2=1)

    // 4. Verify Frame 2 is now visible
    #1000ns;
    check_rx_fifo(2, '{8'hAA, 8'hBB});

    `uvm_info("TEST", "RX-07: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
