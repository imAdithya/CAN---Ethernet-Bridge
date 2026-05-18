// RX-09: Data Integrity (RX)
class can_rx_integrity_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_integrity_test)

  function new(string name = "can_rx_integrity_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-09: Data Integrity Test", UVM_LOW)

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

    // 2. Inject Frame with Pattern 0xAA, 0x55
    `uvm_info("TEST", "Injecting Frame with 0xAA/0x55 pattern...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h7FF; rx_seq.dlc = 8;
    rx_seq.data = '{8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55};
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(8, '{8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55});

    // 3. Inject Frame with all 0xFF
    `uvm_info("TEST", "Injecting Frame with 0xFF pattern...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h001; rx_seq.dlc = 8;
    rx_seq.data = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(8, '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF});

    // 4. Inject Frame with all 0x00
    `uvm_info("TEST", "Injecting Frame with 0x00 pattern...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h555; rx_seq.dlc = 8;
    rx_seq.data = '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(8, '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00});

    `uvm_info("TEST", "RX-09: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
