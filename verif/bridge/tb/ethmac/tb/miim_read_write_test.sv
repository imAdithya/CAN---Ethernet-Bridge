// miim_read_write_test.sv - MIIM-01: MIIM Read/Write Test
class miim_read_write_test extends base_test;
  `uvm_component_utils(miim_read_write_test)

  function new(string name = "miim_read_write_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "disable_rx_check", 1);
    uvm_config_db#(bit)::set(this, "m_env.m_scoreboard", "miim_check_enabled", 1);
  endfunction

  virtual task run_phase(uvm_phase phase);
    miim_read_write_seq seq;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting MIIM Read/Write Test (MIIM-01)...", UVM_LOW)

    m_host_cfg.vif.rst = 1;
    #200ns;
    m_host_cfg.vif.rst = 0;
    #200ns;

    seq = miim_read_write_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    #5000ns;
    `uvm_info(get_type_name(), "MIIM Read/Write Test (MIIM-01) Finished.", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
