// REG-01: Register Access Test
class bridge_reg_access_test extends bridge_base_test;
  `uvm_component_utils(bridge_reg_access_test)

  function new(string name = "bridge_reg_access_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bridge_reg_access_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting bridge register access test (REG-01)...", UVM_MEDIUM)

    // Wait for reset to complete
    #100ns;

    seq = bridge_reg_access_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "REG-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
