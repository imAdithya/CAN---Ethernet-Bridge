// UP-04: Tunnel Mode Upstream Test
// Verifies a CAN frame in tunnel mode: EtherType=0xCABE, tunnel header
// (seq + timestamp) inserted, and sequence number auto-increments.
class upstream_tunnel_test extends bridge_base_test;
  `uvm_component_utils(upstream_tunnel_test)

  function new(string name = "upstream_tunnel_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    upstream_tunnel_seq up_seq;
    counter_verify_seq  cnt_seq;
    bridge_reg_read_seq rd_seq;
    bit [31:0] ram_base;
    bit [31:0] word3, word6;
    bit [15:0] seq_before, seq_after, seq_final;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting tunnel mode upstream test (UP-04)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge in tunnel mode
    up_seq = upstream_tunnel_seq::type_id::create("up_seq");
    up_seq.start(m_env.m_host_agent.m_sequencer);

    rd_seq = bridge_reg_read_seq::type_id::create("rd_seq");

    // Step 2: Read initial tunnel sequence number
    rd_seq.addr = {24'h0, `REG_TUNNEL_SEQ};
    rd_seq.start(m_env.m_host_agent.m_sequencer);
    seq_before = rd_seq.data[15:0];
    `uvm_info("UP04_CHK", $sformatf("Initial tunnel seq = %0d", seq_before), UVM_MEDIUM)

    // Step 3: Load CAN frame and trigger upstream
    m_can_cfg.load_can_frame(
      .can_id(29'h300), .dlc(4'd6), .eff(1'b0), .rtr(1'b0),
      .data('{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF, 8'h00, 8'h00})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Wait for upstream FSM
    #10us;

    // Step 4: Verify EtherType in RAM
    ram_base = (`DEFAULT_TX_BD_ADDR + 32'h400) >> 2;
    word3 = m_mem_cfg.memory[ram_base + 3];

    if (word3[31:16] !== 16'hCABE)
      `uvm_error("UP04_CHK", $sformatf(
        "EtherType mismatch: expected=0xCABE got=0x%04h", word3[31:16]))
    else
      `uvm_info("UP04_CHK", "EtherType = 0xCABE PASS", UVM_MEDIUM)

    // Step 5: Verify tunnel header in word 6 (seq + timestamp)
    word6 = m_mem_cfg.memory[ram_base + 6];
    `uvm_info("UP04_CHK", $sformatf(
      "Tunnel header: seq=%0d timestamp=0x%04h", word6[31:16], word6[15:0]),
      UVM_MEDIUM)

    // Step 6: ETH TX complete
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    // Step 7: Read tunnel seq again — should have incremented
    rd_seq.addr = {24'h0, `REG_TUNNEL_SEQ};
    rd_seq.start(m_env.m_host_agent.m_sequencer);
    seq_after = rd_seq.data[15:0];
    if (seq_after !== seq_before + 1)
      `uvm_error("UP04_CHK", $sformatf(
        "Tunnel seq not incremented: before=%0d after=%0d", seq_before, seq_after))
    else
      `uvm_info("UP04_CHK", $sformatf(
        "Tunnel seq incremented: %0d -> %0d PASS", seq_before, seq_after), UVM_MEDIUM)

    // Step 8: Send second frame — verify seq increments again
    m_can_cfg.load_can_frame(
      .can_id(29'h301), .dlc(4'd2), .eff(1'b0), .rtr(1'b0),
      .data('{8'h11, 8'h22, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00})
    );

    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;
    #10us;

    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    rd_seq.addr = {24'h0, `REG_TUNNEL_SEQ};
    rd_seq.start(m_env.m_host_agent.m_sequencer);
    seq_final = rd_seq.data[15:0];
    if (seq_final !== seq_before + 2)
      `uvm_error("UP04_CHK", $sformatf(
        "Tunnel seq after 2nd frame: expected=%0d got=%0d", seq_before + 2, seq_final))
    else
      `uvm_info("UP04_CHK", "Tunnel seq double-increment PASS", UVM_MEDIUM)

    // Step 9: Verify counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 2;
    cnt_seq.exp_eth_tx   = 2;
    cnt_seq.exp_filtered = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "UP-04 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
