// ARB-01: Arbiter Contention Test
// Triggers upstream (CAN RX IRQ) and downstream (ETH RX IRQ) simultaneously.
// Verifies both FSMs activate, the arbiter handles contention, and both
// frames are processed correctly without data corruption or deadlock.
class arbiter_contention_test extends bridge_base_test;
  `uvm_component_utils(arbiter_contention_test)

  function new(string name = "arbiter_contention_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    arbiter_contention_seq cfg_seq;
    counter_verify_seq     cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  dn_data[8];

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting arbiter contention test (ARB-01)...", UVM_MEDIUM)
    #100ns;

    cfg_seq = arbiter_contention_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // Prepare upstream CAN frame
    m_can_cfg.load_can_frame(
      .can_id(29'h555), .dlc(4'd4), .eff(1'b0), .rtr(1'b0),
      .data('{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    // Prepare downstream ETH frame
    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;
    dn_data = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88};
    downstream_frame_builder::build_gateway_frame(
      m_mem_cfg, frame_ptr,
      .can_id(29'h666), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data(dn_data)
    );
    m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

    // Trigger BOTH interrupts on the same cycle
    `uvm_info("ARB01", "Triggering simultaneous CAN RX + ETH RX interrupts...", UVM_MEDIUM)
    m_can_cfg.vif.can_rx_irq = 1'b1;
    m_mem_cfg.vif.eth_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    m_mem_cfg.vif.eth_rx_irq = 1'b0;

    // Wait for both FSMs to process (upstream writes ETH, downstream writes CAN)
    #15us;

    // Upstream needs ETH TX IRQ to complete
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;

    // Downstream needs CAN TX IRQ to complete
    m_can_cfg.vif.can_tx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_tx_irq = 1'b0;

    // Wait for both FSMs to return to IDLE
    #10us;

    // Verify counters — both directions processed
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 1;  // upstream
    cnt_seq.exp_eth_tx   = 1;  // upstream
    cnt_seq.exp_eth_rx   = 1;  // downstream
    cnt_seq.exp_can_tx   = 1;  // downstream
    cnt_seq.exp_filtered = 0;
    cnt_seq.exp_errors   = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "ARB-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
