class wb_can_reg_reset_test extends uvm_test;
  `uvm_component_utils(wb_can_reg_reset_test)

  wb_can_env env;
  virtual wb_can_if vif;

  function new(string name = "wb_can_reg_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
    
    if (!uvm_config_db#(virtual wb_can_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "Virtual interface not found in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    wb_can_reg_reset_seq seq_reset;
    wb_can_reg_access_seq seq_access; // We use this purely to corrupt memory first
    
    phase.raise_objection(this);

    // Initial wait for normal startup reset to finish out
    wait(vif.rst == 0);
    `uvm_info("TEST", "Starting WB-04 Register Reset Integrity Test", UVM_LOW)

    // PHASE 1: Execute directed stimulus to fill all registers with data so we aren't
    // just reading zeros that were already there.
    `uvm_info("TEST", "Phase 1 / 3: Writing non-default data into all CAN registers", UVM_LOW)
    seq_access = wb_can_reg_access_seq::type_id::create("seq_access");
    seq_access.start(env.agt.sequencer);

    // We'll pause a few beats
    #100ns;

    // PHASE 2: Force an immediate external Hardware Reset to the CAN Controller
    `uvm_info("TEST", "Phase 2 / 3: ASSERTING EXTERNAL HARDWARE RESET...", UVM_LOW)
    vif.rst = 1;
    #100ns;
    vif.rst = 0;
    #100ns;
    
    // PHASE 3: Read everything and verify the hardware wiped the registers back to default
    `uvm_info("TEST", "Phase 3 / 3: Checking Default Hardware Specs Post-Reset", UVM_LOW)
    seq_reset = wb_can_reg_reset_seq::type_id::create("seq_reset");
    seq_reset.start(env.agt.sequencer);

    `uvm_info("TEST", "WB-04 Register Reset Test Complete", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
