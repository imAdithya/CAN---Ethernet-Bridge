// RX-03: Filter Masking (AMR)
class can_rx_masking_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_masking_test)

  function new(string name = "can_rx_masking_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-03: Filter Masking Test", UVM_LOW)

    // 1. Configure DUT: Single Filter, Mask bit 0 of ACR0
    write_reg(8'h1F, 8'h80); // PeliCAN
    write_reg(8'h00, 8'h09); // Reset, Single Filter
    // BTR0, BTR1
    write_reg(8'h06, 8'h00);
    write_reg(8'h07, 8'h25);
    
    // ACR0 = 0x24 (ID=100100xx)
    write_reg(8'h10, 8'h24); 
    // AMR0 = 0x01 (Ignore LSB of ACR0, which is ID3)
    write_reg(8'h14, 8'h01);
    
    // Pass everything else
    write_reg(8'h15, 8'hFF);
    write_reg(8'h16, 8'hFF);
    write_reg(8'h17, 8'hFF);

    write_reg(8'h00, 8'h08); // Operating Mode
    #1000ns;

    // 2. Inject Frame with ID 0x120 (SFF) -> ID[10:3]=0x24. LSB=0. Should match.
    `uvm_info("TEST", "Injecting ID=0x120 (Matches ACR0 bit 0=0)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h120; rx_seq.dlc = 1; rx_seq.data[0] = 8'h11;
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(1, '{8'h11});

    // 3. Inject Frame with ID 0x128 (SFF) -> ID[10:3]=0x25. LSB=1. 
    // Wait, SFF ID bit 3 is the LSB of ACR0.
    // ID 0x128 = 001 0010 1000 binary.
    // Bits [10:3] = 0010 0101 (0x25).
    // Our ACR0=0x24, AMR0=0x01. So it matches 0x24 OR 0x25!
    `uvm_info("TEST", "Injecting ID=0x128 (Matches due to AMR0 mask)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h128; rx_seq.dlc = 1; rx_seq.data[0] = 8'h22;
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(1, '{8'h22});

    `uvm_info("TEST", "RX-03: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
