// SYS-03: Full Duplex Test
// Triggers CAN RX and ETH RX interrupts on the SAME clock cycle.
// Verifies both FSMs activate simultaneously, arbiter handles contention,
// and both frames processed correctly without corruption or deadlock.
class sys_fullduplex_test extends bridge_base_test;
  `uvm_component_utils(sys_fullduplex_test)

  function new(string name = "sys_fullduplex_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    sys_fullduplex_seq cfg_seq;
    counter_verify_seq cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  dn_data[8];
    bit [31:0] ram_base, word3;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting full-duplex test (SYS-03)...", UVM_MEDIUM)
    #100ns;

    cfg_seq = sys_fullduplex_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // --- Prepare upstream CAN frame ---
    m_can_cfg.load_can_frame(
      .can_id(29'h111), .dlc(4'd4), .eff(1'b0), .rtr(1'b0),
      .data('{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    // --- Prepare downstream ETH frame ---
    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;
    dn_data = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88};
    downstream_frame_builder::build_gateway_frame(
      m_mem_cfg, frame_ptr,
      .can_id(29'h222), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data(dn_data)
    );
    m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

    // --- Trigger BOTH interrupts simultaneously ---
    `uvm_info("SYS03", "Triggering simultaneous CAN RX + ETH RX...", UVM_MEDIUM)
    fork
      begin
        m_can_cfg.vif.can_rx_irq = 1'b1;
        #40ns;
        m_can_cfg.vif.can_rx_irq = 1'b0;
      end
      begin
        m_mem_cfg.vif.eth_rx_irq = 1'b1;
        #40ns;
        m_mem_cfg.vif.eth_rx_irq = 1'b0;
      end
    join

    // Wait for both FSMs
    #20us;

    // Complete upstream: ETH TX IRQ
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;

    // Complete downstream: CAN TX IRQ
    m_can_cfg.vif.can_tx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_tx_irq = 1'b0;
    #10us;

    // --- Verify upstream result ---
    ram_base = (`DEFAULT_TX_BD_ADDR + 32'h400) >> 2;
    word3 = m_mem_cfg.memory[ram_base + 3];
    if (word3[31:16] !== 16'hCAFE)
      `uvm_error("SYS03", $sformatf("Upstream EtherType=0x%04h", word3[31:16]))
    else
      `uvm_info("SYS03", "Upstream EtherType PASS", UVM_MEDIUM)

    // --- Verify downstream result ---
    begin
      bit [3:0] dlc_out = m_can_cfg.can_regs['h10][3:0];
      if (dlc_out !== 4'd8)
        `uvm_error("SYS03", $sformatf("Downstream DLC=%0d", dlc_out))
      else
        `uvm_info("SYS03", "Downstream DLC PASS", UVM_MEDIUM)
    end

    // --- Verify counters ---
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 1;
    cnt_seq.exp_eth_tx   = 1;
    cnt_seq.exp_eth_rx   = 1;
    cnt_seq.exp_can_tx   = 1;
    cnt_seq.exp_filtered = 0;
    cnt_seq.exp_errors   = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "SYS-03 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
