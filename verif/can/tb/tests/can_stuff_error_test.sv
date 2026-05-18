// ERR-08: Stuff Error Test
class can_stuff_error_test extends uvm_test;
  `uvm_component_utils(can_stuff_error_test)
  wb_can_env env;
  can_bus_pkg::can_bus_agent can_agt;

  function new(string name = "can_stuff_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "can_agt", "is_active", UVM_PASSIVE);
    can_agt = can_bus_pkg::can_bus_agent::type_id::create("can_agt", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    can_agt.monitor.item_collected_port.connect(env.scb.can_export);
    can_agt.monitor.item_collected_port.connect(env.tx_cov.can_export);
    can_agt.monitor.item_collected_port.connect(env.rx_cov.can_export);
    can_agt.monitor.item_collected_port.connect(env.prot_cov.can_export);
  endfunction

  task run_phase(uvm_phase phase);
    can_rx_frame_seq rx_seq;
    virtual cb_if vif;
    phase.raise_objection(this);
    
    rx_seq = can_rx_frame_seq::type_id::create("rx_seq");
    vif = can_bus_pkg::static_vif;

    #300ns;
    `uvm_info("TEST", "Starting ERR-08: Stuff Error Test", UVM_LOW)
    
    // Configure DUT to be in PeliCAN mode and Operating mode
    begin
      wb_can_trans req = wb_can_trans::type_id::create("req");
      req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; env.agt.sequencer.execute_item(req); // Reset=1
      req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; env.agt.sequencer.execute_item(req); // PeliCAN=1
      req.addr = 8'h00; req.we = 1'b1; req.data = 8'h00; env.agt.sequencer.execute_item(req); // Reset=0
    end

    fork
      begin
        rx_seq.id = 11'h123; rx_seq.dlc = 8;
        rx_seq.start(can_agt.sequencer);
      end
      begin
        wait(vif.can_rx === 0); // Start of frame from agent
        #30us; // Wait until Data field (approx bit 35-40)
        uvm_hdl_force("top.u_can_top.rx_i", 0); // Force dominant for 6+ consecutive bits
        #10us;
        uvm_hdl_release("top.u_can_top.rx_i");
      end
    join
    
    #10us;
    // Read ECC
    begin
      wb_can_trans req = wb_can_trans::type_id::create("req");
      req.addr = 8'h0C; req.we = 1'b0;
      env.agt.sequencer.execute_item(req);
      `uvm_info("TEST", $sformatf("Post-Error ECC = 0x%0h", req.data), UVM_LOW)
    end

    #50000ns;
    `uvm_info("TEST", "ERR-08: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
