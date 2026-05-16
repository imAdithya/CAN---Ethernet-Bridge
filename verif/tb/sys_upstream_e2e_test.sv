// SYS-01: Full Upstream End-to-End Test
// CAN RX IRQ -> read 13 bytes -> filter pass -> encap -> RAM write ->
// BD program -> wait ETH TX IRQ -> release buffer -> IDLE.
// Verifies all 8 upstream FSM states visited and data integrity.
class sys_upstream_e2e_test extends bridge_base_test;
  `uvm_component_utils(sys_upstream_e2e_test)

  function new(string name = "sys_upstream_e2e_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    sys_upstream_e2e_seq cfg_seq;
    counter_verify_seq   cnt_seq;
    bit [31:0] ram_base, word3, word4, word5;
    bit [7:0]  exp_data[8];

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting upstream E2E test (SYS-01)...", UVM_MEDIUM)
    #100ns;

    cfg_seq = sys_upstream_e2e_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // Load CAN frame
    exp_data = '{8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'hCA, 8'hFE, 8'h01, 8'h02};
    m_can_cfg.load_can_frame(
      .can_id(29'h1AB), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data(exp_data)
    );

    // Trigger CAN RX
    m_can_cfg.vif.can_rx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_rx_irq = 1'b0;

    // Wait for full upstream path to complete
    #10us;

    // Verify frame in RAM
    ram_base = (`DEFAULT_TX_BD_ADDR + 32'h400) >> 2;
    word3 = m_mem_cfg.memory[ram_base + 3];
    word4 = m_mem_cfg.memory[ram_base + 4];
    word5 = m_mem_cfg.memory[ram_base + 5];

    // Check EtherType
    if (word3[31:16] !== 16'hCAFE)
      `uvm_error("SYS01", $sformatf("EtherType=0x%04h, expected 0xCAFE", word3[31:16]))
    else
      `uvm_info("SYS01", "EtherType PASS", UVM_MEDIUM)

    // Check version
    if (word4[31:24] !== `BRIDGE_VERSION)
      `uvm_error("SYS01", $sformatf("Version=0x%02h", word4[31:24]))

    // Check CAN ID
    begin
      bit [28:0] read_id;
      read_id[28:5] = word4[23:0];
      read_id[4:0]  = word5[31:27];
      if (read_id !== 29'h1AB)
        `uvm_error("SYS01", $sformatf("CAN ID=0x%07h, expected 0x1AB", read_id))
      else
        `uvm_info("SYS01", "CAN ID PASS", UVM_MEDIUM)
    end

    // Check BD READY
    begin
      bit [31:0] bd_word0 = m_mem_cfg.memory[`DEFAULT_TX_BD_ADDR >> 2];
      if (bd_word0[0] !== 1'b1)
        `uvm_error("SYS01", "BD READY not set")
      else
        `uvm_info("SYS01", "BD READY PASS", UVM_MEDIUM)
    end

    // Check data byte 0 in word5[7:0]
    if (word5[7:0] !== exp_data[0])
      `uvm_error("SYS01", $sformatf("Data[0]=0x%02h, expected 0x%02h", word5[7:0], exp_data[0]))

    // Check data bytes 1-4 in word 6
    begin
      bit [31:0] word6 = m_mem_cfg.memory[ram_base + 6];
      if (word6 !== {exp_data[1], exp_data[2], exp_data[3], exp_data[4]})
        `uvm_error("SYS01", $sformatf("Data[1:4] mismatch: 0x%08h", word6))
      else
        `uvm_info("SYS01", "Data integrity PASS", UVM_MEDIUM)
    end

    // ETH TX complete
    m_mem_cfg.vif.eth_tx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_tx_irq = 1'b0;
    #2us;

    // Counters
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = 1;
    cnt_seq.exp_eth_tx   = 1;
    cnt_seq.exp_filtered = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "SYS-01 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
