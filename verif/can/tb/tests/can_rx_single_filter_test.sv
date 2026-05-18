// RX-01: Single Filter Match (SFF/EFF)
class can_rx_single_filter_test extends uvm_test;
  `uvm_component_utils(can_rx_single_filter_test)
  wb_can_env env;
  can_bus_pkg::can_bus_agent can_agt;
  can_rx_frame_seq rx_seq;
  wb_can_single_access_seq wb_seq;

  function new(string name = "can_rx_single_filter_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    
    // Create CAN bus agent in ACTIVE mode for RX injection
    uvm_config_db#(uvm_active_passive_enum)::set(this, "can_agt", "is_active", UVM_ACTIVE);
    can_agt = can_bus_pkg::can_bus_agent::type_id::create("can_agt", this);
    
    rx_seq = can_rx_frame_seq::type_id::create("rx_seq");
    wb_seq = wb_can_single_access_seq::type_id::create("wb_seq");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    can_agt.monitor.item_collected_port.connect(env.scb.can_export);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    
    `uvm_info("TEST", "Starting RX-01: Single Filter Match Test", UVM_LOW)

    // 1. Configure DUT for PeliCAN, Single Filter mode
    `uvm_info("TEST", "Configuring DUT: PeliCAN, Single Filter...", UVM_LOW)
    // CDR.7=1 (PeliCAN)
    write_reg(8'h1F, 8'h80);
    // MOD.0=1 (Reset), MOD.3=1 (Single Filter)
    write_reg(8'h00, 8'h09);
    // BTR0, BTR1
    write_reg(8'h06, 8'h00);
    write_reg(8'h07, 8'h25);
    // ACR0-3: Set pattern (e.g., ID=0x123)
    write_reg(8'h10, 8'h24); // ACR0
    write_reg(8'h11, 8'h60); // ACR1
    write_reg(8'h12, 8'h00); // ACR2
    write_reg(8'h13, 8'h00); // ACR3
    // AMR0-3: Mask bits
    write_reg(8'h14, 8'h00); // AMR0
    write_reg(8'h15, 8'h1F); // AMR1
    write_reg(8'h16, 8'hFF); // AMR2
    write_reg(8'h17, 8'hFF); // AMR3
    
    // MOD.0=0 (Exit Reset)
    write_reg(8'h00, 8'h08); 
    #1000ns;

    // 2. Inject Frame from CAN Agent
    `uvm_info("TEST", "Injecting SFF Frame (ID=0x123)...", UVM_LOW)
    rx_seq.ide = 0;
    rx_seq.id = 29'h123;
    rx_seq.dlc = 4;
    rx_seq.data = '{8'hDE, 8'hAD, 8'hBE, 8'hEF, 0, 0, 0, 0};
    rx_seq.start(can_agt.sequencer);

    // Wait for frame to be processed
    #200000ns;

    // 3. Check Status and Read FIFO
    check_rx_fifo();

    `uvm_info("TEST", "RX-01: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask

  task write_reg(bit [7:0] addr, bit [7:0] data);
    wb_can_trans req = wb_can_trans::type_id::create("req");
    req.addr = addr; req.we = 1; req.data = data;
    // Execute directly on the sequencer
    env.agt.sequencer.execute_item(req);
  endtask

  task check_rx_fifo();
    wb_can_trans req = wb_can_trans::type_id::create("req");
    bit [7:0] status;
    bit [7:0] rx_info, data_byte;

    // Read Status Reg (0x02)
    req.addr = 8'h02; req.we = 0; 
    env.agt.sequencer.execute_item(req);
    status = req.data;
    
    if (status[0] == 1) begin
      `uvm_info("TEST", "Frame successfully received in FIFO!", UVM_LOW)
      // Read Frame Info (0x10)
      req.addr = 8'h10; req.we = 0; env.agt.sequencer.execute_item(req);
      rx_info = req.data;
      `uvm_info("TEST", $sformatf("RX Frame Info: 0x%h (DLC=%0d)", rx_info, rx_info[3:0]), UVM_LOW)
      
      // Read Data
      for (int i=0; i<4; i++) begin
        req.addr = 8'h13 + i; req.we = 0; env.agt.sequencer.execute_item(req);
        data_byte = req.data;
        `uvm_info("TEST", $sformatf("RX Data[%0d]: 0x%h", i, data_byte), UVM_LOW)
      end
    end else begin
      `uvm_error("TEST", "RX FIFO EMPTY! Acceptance Filter might have dropped the frame.")
    end
  endtask

endclass
