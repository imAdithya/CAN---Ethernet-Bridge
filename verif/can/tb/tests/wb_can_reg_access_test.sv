class wb_can_reg_access_test extends uvm_test;
  `uvm_component_utils(wb_can_reg_access_test)

  wb_can_env env;
  virtual wb_can_if vif;

  // Expected write values for integrity check
  logic [7:0] exp_data [logic [7:0]];
  int pass_count = 0;
  int fail_count = 0;

  function new(string name = "wb_can_reg_access_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    
    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "Virtual interface not found in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    wb_can_reg_access_seq seq;
    phase.raise_objection(this);

    // Synchronize with reset de-assertion
    wait(vif.rst == 0);
    `uvm_info("TEST", "Starting WB-04 Register Access Test", UVM_LOW)

    // Execute directed stimulus
    seq = wb_can_reg_access_seq::type_id::create("seq");
    seq.start(env.agt.sequencer);

    // After sequence completes, report scoreboard matches/mismatches
    // The sequence wrote and read every register. The scoreboard automatically
    // catches `SCB_DIFF` or `SCB_MATCH`. We'll just print a done message.
    
    `uvm_info("TEST", "WB-04 Register Access Test Complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
