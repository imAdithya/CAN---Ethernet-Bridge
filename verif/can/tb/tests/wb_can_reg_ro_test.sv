class wb_can_reg_ro_test extends uvm_test;
  `uvm_component_utils(wb_can_reg_ro_test)
  
  wb_can_env env;
  wb_can_reg_ro_seq seq;
  
  function new(string name = "wb_can_reg_ro_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    seq = wb_can_reg_ro_seq::type_id::create("seq_ro");
  endfunction
  
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    
    // Put testbench to sleep briefly to allow hardware to initialize
    // then jump straight into the sequence
    #100ns;

    `uvm_info("TEST", "Starting WB-05 Read-Only Access Test...", UVM_LOW)
    seq.start(env.agt.sequencer);
    `uvm_info("TEST", "WB-05 Read-Only Access Test Complete", UVM_LOW)
    
    // Give scoreboard time to chew final reads
    #100ns;
    
    phase.drop_objection(this);
  endtask
endclass
