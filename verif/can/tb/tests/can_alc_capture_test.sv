// PROT-07: Arbitration Lost Capture (ALC) Test
class can_alc_capture_test extends uvm_test;
  `uvm_component_utils(can_alc_capture_test)
  wb_can_env env;
  can_bus_pkg::can_bus_agent can_agt;
  can_alc_capture_seq seq;

  function new(string name = "can_alc_capture_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "can_agt", "is_active", UVM_PASSIVE);
    can_agt = can_bus_pkg::can_bus_agent::type_id::create("can_agt", this);
    seq = can_alc_capture_seq::type_id::create("seq");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    can_agt.monitor.item_collected_port.connect(env.scb.can_export);
    can_agt.monitor.item_collected_port.connect(env.tx_cov.can_export);
    can_agt.monitor.item_collected_port.connect(env.rx_cov.can_export);
    can_agt.monitor.item_collected_port.connect(env.prot_cov.can_export);
  endfunction

  task run_phase(uvm_phase phase);
    virtual cb_if vif = can_bus_pkg::static_vif;
    phase.raise_objection(this);
    #300ns;
    `uvm_info("TEST", "Starting PROT-07: ALC Capture Test", UVM_LOW)
    
    // 1st time: lose at bit 9 (id20_to_id13 range, ALC=9)
    fork
      seq.start(env.agt.sequencer);
      begin
        wait(vif.can_tx === 0);
        #7.5us; 
        uvm_hdl_force("top.u_can_top.rx_i", 0);
        #1us;
        uvm_hdl_release("top.u_can_top.rx_i");
      end
    join
    
    #100000ns;
    
    // 2nd time: lose at bit 20 (others range, ALC=20)
    fork
      seq.start(env.agt.sequencer);
      begin
        wait(vif.can_tx === 0);
        #16.5us; 
        uvm_hdl_force("top.u_can_top.rx_i", 0);
        #1us;
        uvm_hdl_release("top.u_can_top.rx_i");
      end
    join

    #50000ns;
    `uvm_info("TEST", "PROT-07: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
