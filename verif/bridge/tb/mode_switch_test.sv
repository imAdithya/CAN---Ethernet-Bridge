// MODE-01: Mode Switch Test
class mode_switch_test extends bridge_base_test;
  `uvm_component_utils(mode_switch_test)

  function new(string name = "mode_switch_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    mode_switch_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting mode switch test (MODE-01)...", UVM_MEDIUM)
    #100ns;

    seq = mode_switch_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "MODE-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
