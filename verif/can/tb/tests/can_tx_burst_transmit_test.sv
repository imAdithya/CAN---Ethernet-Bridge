// TX-09: Burst Transmit Verification Test

class can_tx_burst_transmit_test extends uvm_test;
  `uvm_component_utils(can_tx_burst_transmit_test)
  wb_can_env env;
  can_bus_pkg::can_bus_agent can_agt;
  can_tx_burst_transmit_seq burst_seq;

  function new(string name = "can_tx_burst_transmit_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "can_agt", "is_active", UVM_PASSIVE);
    can_agt = can_bus_pkg::can_bus_agent::type_id::create("can_agt", this);
    burst_seq = can_tx_burst_transmit_seq::type_id::create("burst_seq");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    can_agt.monitor.item_collected_port.connect(env.scb.can_export);
    can_agt.monitor.item_collected_port.connect(env.tx_cov.can_export);
    can_agt.monitor.item_collected_port.connect(env.rx_cov.can_export);
    can_agt.monitor.item_collected_port.connect(env.prot_cov.can_export);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #300ns;
    `uvm_info("TEST", "Starting TX-09: Burst Transmit Test (400 random frames)", UVM_LOW)
    burst_seq.start(env.agt.sequencer);
    #50000ns;
    `uvm_info("TEST", "TX-09: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
