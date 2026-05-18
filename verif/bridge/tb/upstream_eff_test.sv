// UP-02: Extended Frame Format (EFF) Upstream Test
// Verifies a CAN frame with 29-bit extended ID (EFF=1) is correctly
// packed into bridge header words 4-5, with flags byte bit 0 = 1.
class upstream_eff_test extends bridge_base_test;
  `uvm_component_utils(upstream_eff_test)

  function new(string name = "upstream_eff_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    upstream_eff_seq   up_seq;
    counter_verify_seq cnt_seq;
    bit [31:0] ram_base;
    bit [31:0] word3, word4, word5;
    bit [7:0]  version, flags;
    bit [28:0] reconstructed_id;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting EFF upstream test (UP-02)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge
    up_seq = upstream_eff_seq::type_id::create("up_seq");
    up_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Load CAN frame with EFF=1, 29-bit ID
    m_can_cfg.load_can_frame(
      .can_id(29'h1ABCDEF), .dlc(4'd4), .eff(1'b1), .rtr(1'b0),
      .data('{8'hA1, 8'hB2, 8'hC3, 8'hD4, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    // Step 3: Trigger CAN RX interrupt
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Step 4: Wait for upstream FSM
    #10us;

    // Step 5: Verify EFF flag in the frame written to RAM
    ram_base = (`DEFAULT_TX_BD_ADDR + 32'h400) >> 2;

    // Word 3: {EtherType, Magic}
    word3 = m_mem_cfg.memory[ram_base + 3];
    if (word3[31:16] !== 16'hCAFE)
      `uvm_error("UP02_CHK", $sformatf("EtherType mismatch: 0x%04h", word3[31:16]))

    // Word 4: {version, can_id[28:5], 1'b0}
    word4 = m_mem_cfg.memory[ram_base + 4];
    version = word4[31:24];

    if (version !== `BRIDGE_VERSION)
      `uvm_error("UP02_CHK", $sformatf("Version mismatch: 0x%02h", version))

    // Word 5: {can_id[4:0], 3'b0, 4'b0, dlc[3:0], 6'b0, rtr, eff, data[7:0]}
    word5 = m_mem_cfg.memory[ram_base + 5];
    flags = word5[9:0];  // rtr at bit 9, eff at bit 8

    // EFF should be in flags bit 0
    if (flags[0] !== 1'b1)
      `uvm_error("UP02_CHK", $sformatf("EFF flag not set in flags byte: 0x%02h", flags))
    else
      `uvm_info("UP02_CHK", "EFF flag correctly set in bridge header PASS", UVM_MEDIUM)

    // Reconstruct CAN ID from words 4-5
    reconstructed_id[28:5] = word4[23:0];     // word4 = {version, can_id[28:5]}
    reconstructed_id[4:0]  = word5[31:27];

    if (reconstructed_id !== 29'h1ABCDEF)
      `uvm_error("UP02_CHK", $sformatf("CAN ID mismatch: expected=0x1ABCDEF got=0x%07h", reconstructed_id))
    else
      `uvm_info("UP02_CHK", "29-bit CAN ID correctly packed PASS", UVM_MEDIUM)

    // Step 6: ETH TX complete
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    // Step 7: Verify counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 1;
    cnt_seq.exp_eth_tx   = 1;
    cnt_seq.exp_filtered = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "UP-02 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
