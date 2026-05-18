// ERR-01: Error Code Capture (ECC) Reporting Test
class can_ecc_capture_test extends uvm_test;
  `uvm_component_utils(can_ecc_capture_test)
  wb_can_env env;
  can_bus_pkg::can_bus_agent can_agt;
  can_ecc_capture_seq seq;

  function new(string name = "can_ecc_capture_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "can_agt", "is_active", UVM_PASSIVE);
    can_agt = can_bus_pkg::can_bus_agent::type_id::create("can_agt", this);
    seq = can_ecc_capture_seq::type_id::create("seq");
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
    `uvm_info("TEST", "Starting ERR-01: ECC Capture Test", UVM_LOW)
    seq.start(env.agt.sequencer);
    #50000ns;
    `uvm_info("TEST", "ERR-01: TEST COMPLETE", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
