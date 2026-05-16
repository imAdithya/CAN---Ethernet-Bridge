// CNT-01: Counter Verification Test
class counter_verify_test extends bridge_base_test;
  `uvm_component_utils(counter_verify_test)

  function new(string name = "counter_verify_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bridge_config_seq  cfg_seq;
    counter_verify_seq cnt_seq;
    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting counter verification test (CNT-01)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge (gateway, filter with accept list)
    cfg_seq = bridge_config_seq::type_id::create("cfg_seq");
    cfg_seq.mode      = 2'b01;
    cfg_seq.enable    = 1;
    cfg_seq.filter_en = 1;
    cfg_seq.filter_mode = 0;  // accept list
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Send 3 upstream CAN frames (1 filtered, 2 forwarded)
    // Frame 1: matching ID → forwarded
    m_can_cfg.load_can_frame(29'h000, 4'd8, 1'b0, 1'b0,
      '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88});

    m_can_cfg.vif.can_rx_irq = 1;
    #40ns; m_can_cfg.vif.can_rx_irq = 0;
    #10us;
    m_mem_cfg.vif.eth_tx_irq = 1;
    #40ns; m_mem_cfg.vif.eth_tx_irq = 0;
    #2us;

    // Frame 2: matching ID → forwarded
    m_can_cfg.vif.can_rx_irq = 1;
    #40ns; m_can_cfg.vif.can_rx_irq = 0;
    #10us;
    m_mem_cfg.vif.eth_tx_irq = 1;
    #40ns; m_mem_cfg.vif.eth_tx_irq = 0;
    #2us;

    // Frame 3: non-matching ID → filtered
    m_can_cfg.load_can_frame(29'h7FF, 4'd4, 1'b0, 1'b0,
      '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'h00, 8'h00, 8'h00, 8'h00});

    m_can_cfg.vif.can_rx_irq = 1;
    #40ns; m_can_cfg.vif.can_rx_irq = 0;
    #5us;

    // Step 3: Verify all counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 3;
    cnt_seq.exp_eth_tx   = 2;
    cnt_seq.exp_filtered = 1;
    cnt_seq.exp_eth_rx   = 0;
    cnt_seq.exp_can_tx   = 0;
    cnt_seq.exp_errors   = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "CNT-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
