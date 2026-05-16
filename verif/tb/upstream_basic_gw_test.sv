// UP-01: Basic Gateway Upstream Test
// Verifies a standard CAN frame is correctly encapsulated into an
// Ethernet frame in gateway mode (EtherType=0xCAFE), written to RAM,
// and BD programmed with READY=1.
class upstream_basic_gw_test extends bridge_base_test;
  `uvm_component_utils(upstream_basic_gw_test)

  function new(string name = "upstream_basic_gw_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    upstream_basic_gw_seq up_seq;
    counter_verify_seq    cnt_seq;
    bit [31:0] word3, bd_word0;
    bit [15:0] ethertype;

    phase.raise_objection(this);

    `uvm_info(get_type_name(), "Starting basic gateway upstream test (UP-01)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge via host sequence
    up_seq = upstream_basic_gw_seq::type_id::create("up_seq");
    up_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Load CAN frame into CAN agent register file
    m_can_cfg.load_can_frame(
      .can_id(29'h1AB), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data('{8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'hCA, 8'hFE, 8'h01, 8'h02})
    );

    // Step 3: Trigger CAN RX interrupt → upstream FSM starts
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Step 4: Wait for upstream FSM to write frame to RAM and program BD
    #10us;

    // Step 5: Verify frame data in MEM agent's memory
    word3 = m_mem_cfg.memory[(`DEFAULT_TX_BD_ADDR + 32'h400 + 12) >> 2];
    ethertype = word3[31:16];

    if (ethertype !== 16'hCAFE)
      `uvm_error("UP01_CHK", $sformatf("EtherType mismatch: expected=0xCAFE got=0x%04h", ethertype))
    else
      `uvm_info("UP01_CHK", "EtherType = 0xCAFE PASS", UVM_MEDIUM)

    // Check BD status (READY bit = bit 0 at bd_addr word 0)
    bd_word0 = m_mem_cfg.memory[`DEFAULT_TX_BD_ADDR >> 2];
    if (bd_word0[0] !== 1'b1)
      `uvm_error("UP01_CHK", $sformatf("BD READY bit not set: BD[0]=0x%08h", bd_word0))
    else
      `uvm_info("UP01_CHK", "BD READY=1 PASS", UVM_MEDIUM)

    // Step 6: Simulate ETH TX complete
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
    `uvm_info(get_type_name(), "UP-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
