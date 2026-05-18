// RX-02: Dual Filter Match (SFF/EFF)
class can_rx_dual_filter_test extends can_rx_base_test;
  `uvm_component_utils(can_rx_dual_filter_test)

  function new(string name = "can_rx_dual_filter_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-02: Dual Filter Match Test", UVM_LOW)

    // 1. Configure DUT for PeliCAN, Dual Filter mode (MOD.3=0)
    `uvm_info("TEST", "Configuring DUT: PeliCAN, Dual Filter...", UVM_LOW)
    write_reg(8'h1F, 8'h80); // PeliCAN
    write_reg(8'h00, 8'h01); // Reset Mode, Dual Filter (MOD.3=0)
    write_reg(8'h06, 8'h00); // BTR0
    write_reg(8'h07, 8'h25); // BTR1
    
    // Dual Filter Mapping (SJA1000):
    // Filter 1: ACR0, ACR1[7:4], AMR0, AMR1[7:4]
    // Filter 2: ACR2, ACR3[7:4], AMR2, AMR3[7:4]
    
    // Set Filter 1 to match ID 0x123 (SFF)
    // ID 0x123 -> ID[10:3]=0x24, ID[2:0]=011. ACR0=0x24, ACR1=0x60 (top 4 bits: 0110)
    write_reg(8'h10, 8'h24); // ACR0
    write_reg(8'h11, 8'h60); // ACR1
    write_reg(8'h14, 8'h00); // AMR0
    write_reg(8'h15, 8'h0F); // AMR1 (ignore bottom bits)

    // Set Filter 2 to match ID 0x456
    // ID 0x456 (100 0101 0110) -> ID[10:3]=0x8A, ID[2:0]=110. ACR2=0x8A, ACR3=0xC0
    write_reg(8'h12, 8'h8A); // ACR2
    write_reg(8'h13, 8'hC0); // ACR3
    write_reg(8'h16, 8'h00); // AMR2
    write_reg(8'h17, 8'h0F); // AMR3

    write_reg(8'h00, 8'h00); // Operating Mode
    #1000ns;

    // 2. Inject Frame 1 (Match Filter 1)
    `uvm_info("TEST", "Injecting Frame matching Filter 1 (ID=0x123)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h123; rx_seq.dlc = 2; rx_seq.data = '{8'h11, 8'h22, 0, 0, 0, 0, 0, 0};
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(2, '{8'h11, 8'h22});

    // 3. Inject Frame 2 (Match Filter 2)
    `uvm_info("TEST", "Injecting Frame matching Filter 2 (ID=0x456)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.rtr = 0;
    rx_seq.id = 29'h456; rx_seq.dlc = 3; rx_seq.data = '{8'hAA, 8'hBB, 8'hCC, 0, 0, 0, 0, 0};
    rx_seq.start(can_agt.sequencer);
    #200us;
    check_rx_fifo(3, '{8'hAA, 8'hBB, 8'hCC});

    `uvm_info("TEST", "RX-02: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
