// UP-03: DLC Sweep Upstream Test
// Sends CAN frames with DLC values 0 through 8. Verifies correct frame
// length calculation and padding to 60-byte minimum for all sizes.
class upstream_dlc_sweep_test extends bridge_base_test;
  `uvm_component_utils(upstream_dlc_sweep_test)

  function new(string name = "upstream_dlc_sweep_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    upstream_dlc_sweep_seq up_seq;
    counter_verify_seq     cnt_seq;
    int dlc_val;
    bit [7:0]  test_data[8];
    bit [31:0] bd_word0;
    bit [10:0] frame_len;
    int expected_len;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting DLC sweep upstream test (UP-03)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge
    up_seq = upstream_dlc_sweep_seq::type_id::create("up_seq");
    up_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Send 9 frames with DLC 0..8
    for (dlc_val = 0; dlc_val <= 8; dlc_val++) begin

      // Fill data with pattern based on DLC
      for (int i = 0; i < 8; i++)
        test_data[i] = (i < dlc_val) ? (dlc_val * 16 + i) : 8'h00;

      m_can_cfg.load_can_frame(
        .can_id(29'h050 + dlc_val), .dlc(dlc_val[3:0]),
        .eff(1'b0), .rtr(1'b0), .data(test_data)
      );

      // Trigger CAN RX
      m_can_cfg.vif.can_rx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_rx_irq = 1'b0;

      // Wait for upstream to complete
      #10us;

      // Check BD status word for frame length
      bd_word0 = m_mem_cfg.memory[`DEFAULT_TX_BD_ADDR >> 2];
      frame_len = bd_word0[31:21];
      // Gateway: 14 (ETH) + 9 (bridge) + DLC, min 60
      expected_len = (14 + 9 + dlc_val) < 60 ? 60 : (14 + 9 + dlc_val);

      if (frame_len !== expected_len[10:0])
        `uvm_error("UP03_CHK", $sformatf(
          "DLC=%0d: frame_len mismatch: expected=%0d got=%0d",
          dlc_val, expected_len, frame_len))
      else
        `uvm_info("UP03_CHK", $sformatf(
          "DLC=%0d: frame_len=%0d PASS", dlc_val, frame_len), UVM_MEDIUM)

      // ETH TX complete
      m_mem_cfg.vif.eth_tx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_tx_irq = 1'b0;
      #2us;
    end

    // Additional coverage: EFF+DLC sweep (hits {dlc_X, extended} cross bins)
    for (dlc_val = 0; dlc_val <= 8; dlc_val++) begin
      for (int i = 0; i < 8; i++)
        test_data[i] = (i < dlc_val) ? 8'hEE : 8'h00;

      m_can_cfg.load_can_frame(
        .can_id(29'h1ABCDE0 + dlc_val), .dlc(dlc_val[3:0]),
        .eff(1'b1), .rtr(1'b0), .data(test_data)
      );

      m_can_cfg.vif.can_rx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_rx_irq = 1'b0;
      #10us;

      m_mem_cfg.vif.eth_tx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_tx_irq = 1'b0;
      #2us;
    end

    // Additional coverage: RTR frame (hits remote_frame bin)
    m_can_cfg.load_can_frame(
      .can_id(29'h0FF), .dlc(4'd0),
      .eff(1'b0), .rtr(1'b1), .data('{8'h0,8'h0,8'h0,8'h0,8'h0,8'h0,8'h0,8'h0})
    );
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    #10us;
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    // Step 3: Verify counters — 9 + 9 + 1 = 19 frames
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 19;
    cnt_seq.exp_eth_tx   = 19;
    cnt_seq.exp_filtered = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "UP-03 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
