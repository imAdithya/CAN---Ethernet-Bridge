// MODE-02: Bridge Disable Test
class bridge_disable_test extends bridge_base_test;
  `uvm_component_utils(bridge_disable_test)

  function new(string name = "bridge_disable_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bridge_disable_seq seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting bridge disable test (MODE-02)...", UVM_MEDIUM)
    #100ns;

    // Trigger some interrupts BEFORE disabling to establish baseline
    // (should increment counters since bridge starts enabled)

    // Now run the disable sequence
    seq = bridge_disable_seq::type_id::create("seq");
    seq.start(m_env.m_host_agent.m_sequencer);

    // While bridge is disabled, fire CAN IRQ — should be ignored
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    #5us;

    // Fire ETH RX IRQ — should also be ignored
    m_mem_cfg.vif.eth_rx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_rx_irq = 1'b0;
    #5us;

    #500ns;
    `uvm_info(get_type_name(), "MODE-02 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
