// DN-01: Basic Gateway Downstream Test
// Receives a valid gateway Ethernet frame and verifies the CAN frame
// is correctly extracted and transmitted on the CAN bus.
class downstream_basic_gw_test extends bridge_base_test;
  `uvm_component_utils(downstream_basic_gw_test)

  function new(string name = "downstream_basic_gw_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    downstream_basic_gw_seq dn_seq;
    counter_verify_seq      cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  exp_data[8];

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting basic gateway downstream test (DN-01)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge
    dn_seq = downstream_basic_gw_seq::type_id::create("dn_seq");
    dn_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Build a valid gateway frame in memory
    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;  // Frame data at BD + 0x100

    exp_data = '{8'hA1, 8'hB2, 8'hC3, 8'hD4, 8'hE5, 8'hF6, 8'h07, 8'h18};

    downstream_frame_builder::build_gateway_frame(
      m_mem_cfg, frame_ptr,
      .can_id(29'h1AB), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data(exp_data)
    );

    // Step 3: Set up RX BD pointing to the frame
    m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

    // Step 4: Trigger ETH RX interrupt → downstream FSM starts
    m_mem_cfg.vif.eth_rx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_rx_irq = 1'b0;

    // Step 5: Wait for downstream FSM to read, validate, decap, and write CAN
    #15us;

    // Step 6: Trigger CAN TX complete interrupt
    m_can_cfg.vif.can_tx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_tx_irq = 1'b0;

    // Wait for FREE_BD to complete
    #5us;

    // Step 7: Verify CAN frame was written to CAN agent registers
    begin
      bit [7:0] reg_info = m_can_cfg.can_regs['h10];
      bit [3:0] written_dlc = reg_info[3:0];
      bit       written_eff = reg_info[7];
      bit       written_rtr = reg_info[6];

      if (written_dlc !== 4'd8)
        `uvm_error("DN01_CHK", $sformatf("DLC mismatch: expected=8 got=%0d", written_dlc))
      else
        `uvm_info("DN01_CHK", "DLC=8 PASS", UVM_MEDIUM)

      if (written_eff !== 1'b0)
        `uvm_error("DN01_CHK", "EFF should be 0")

      // Check data bytes
      for (int i = 0; i < 8; i++) begin
        if (m_can_cfg.can_regs['h15 + i] !== exp_data[i])
          `uvm_error("DN01_CHK", $sformatf(
            "Data[%0d] mismatch: expected=0x%02h got=0x%02h",
            i, exp_data[i], m_can_cfg.can_regs['h15 + i]))
      end
      `uvm_info("DN01_CHK", "CAN frame data integrity PASS", UVM_MEDIUM)
    end

    // Step 8: Verify TX request was issued (cmd reg = 0x01)
    if (m_can_cfg.can_regs['h01] !== `CAN_CMD_TX_REQ)
      `uvm_error("DN01_CHK", $sformatf(
        "CAN TX request not issued: CMD=0x%02h", m_can_cfg.can_regs['h01]))
    else
      `uvm_info("DN01_CHK", "CAN TX request issued PASS", UVM_MEDIUM)

    // Step 9: Verify counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = 1;
    cnt_seq.exp_can_tx = 1;
    cnt_seq.exp_errors = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "DN-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
