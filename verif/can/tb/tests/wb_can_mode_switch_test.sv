class wb_can_mode_switch_test extends uvm_test;
  `uvm_component_utils(wb_can_mode_switch_test)
  
  wb_can_env env;
  wb_can_mode_switch_seq seq;
  
  function new(string name = "wb_can_mode_switch_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    seq = wb_can_mode_switch_seq::type_id::create("seq_switch");
  endfunction
  
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    #100ns;
    `uvm_info("TEST", "Starting WB-07 Mode Switching Architectural Proofs Test...", UVM_LOW)
    seq.start(env.agt.sequencer);
    `uvm_info("TEST", "WB-07 Mode Switching Test Complete", UVM_LOW)

    #100ns;
    phase.drop_objection(this);
  endtask
endclass
