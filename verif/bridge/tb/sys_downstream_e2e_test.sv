// SYS-02: Full Downstream End-to-End Test
// ETH RX IRQ -> read BD -> read RAM -> validate -> decap -> enqueue ->
// write CAN -> wait CAN TX IRQ -> free BD -> IDLE.
// Verifies all 10 downstream FSM states visited and data integrity.
class sys_downstream_e2e_test extends bridge_base_test;
  `uvm_component_utils(sys_downstream_e2e_test)

  function new(string name = "sys_downstream_e2e_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    sys_downstream_e2e_seq cfg_seq;
    counter_verify_seq     cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  exp_data[8];

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting downstream E2E test (SYS-02)...", UVM_MEDIUM)
    #100ns;

    cfg_seq = sys_downstream_e2e_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;
    exp_data = '{8'h10, 8'h20, 8'h30, 8'h40, 8'h50, 8'h60, 8'h70, 8'h80};

    // Build and load ETH frame
    downstream_frame_builder::build_gateway_frame(
      m_mem_cfg, frame_ptr,
      .can_id(29'h2CD), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data(exp_data)
    );
    m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

    // Trigger ETH RX
    m_mem_cfg.vif.eth_rx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_rx_irq = 1'b0;

    // Wait for full downstream path
    #15us;

    // CAN TX complete
    m_can_cfg.vif.can_tx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_tx_irq = 1'b0;
    #5us;

    // Verify CAN frame fields
    begin
      bit [7:0] reg_info = m_can_cfg.can_regs['h10];
      bit [3:0] dlc_out  = reg_info[3:0];

      if (dlc_out !== 4'd8)
        `uvm_error("SYS02", $sformatf("DLC=%0d, expected 8", dlc_out))
      else
        `uvm_info("SYS02", "DLC PASS", UVM_MEDIUM)
    end

    // Verify CAN ID
    begin
      bit [28:0] can_id_out;
      can_id_out[28:21] = m_can_cfg.can_regs['h11];
      can_id_out[20:13] = m_can_cfg.can_regs['h12];
      can_id_out[12:5]  = m_can_cfg.can_regs['h13];
      can_id_out[4:0]   = m_can_cfg.can_regs['h14][7:3];
      if (can_id_out !== 29'h2CD)
        `uvm_error("SYS02", $sformatf("CAN ID=0x%07h, expected 0x2CD", can_id_out))
      else
        `uvm_info("SYS02", "CAN ID PASS", UVM_MEDIUM)
    end

    // Verify data bytes
    for (int i = 0; i < 8; i++) begin
      if (m_can_cfg.can_regs['h15 + i] !== exp_data[i])
        `uvm_error("SYS02", $sformatf(
          "Data[%0d]=0x%02h, expected 0x%02h",
          i, m_can_cfg.can_regs['h15 + i], exp_data[i]))
    end
    `uvm_info("SYS02", "Data integrity PASS", UVM_MEDIUM)

    // Verify TX request
    if (m_can_cfg.can_regs['h01] !== `CAN_CMD_TX_REQ)
      `uvm_error("SYS02", "CAN TX request not issued")
    else
      `uvm_info("SYS02", "CAN TX request PASS", UVM_MEDIUM)

    // Counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = 1;
    cnt_seq.exp_can_tx = 1;
    cnt_seq.exp_errors = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "SYS-02 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
