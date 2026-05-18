// REG-02: Register Reset Default Values Test
class bridge_reg_reset_test extends bridge_base_test;
  `uvm_component_utils(bridge_reg_reset_test)

  function new(string name = "bridge_reg_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bridge_reg_reset_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting reset default value test (REG-02)...", UVM_MEDIUM)

    // Reset is applied in tb_bridge_top.sv at time 0.
    // Wait for it to release, then check defaults immediately
    #100ns;

    seq = bridge_reg_reset_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "REG-02 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
