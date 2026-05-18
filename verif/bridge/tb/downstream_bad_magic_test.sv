// DN-05: Bad Magic Byte Downstream Test
// Receives an Ethernet frame with correct EtherType (0xCAFE) but wrong magic bytes.
// Verifies frame is dropped at VALIDATE, cnt_errors incremented, BD freed.
class downstream_bad_magic_test extends bridge_base_test;
  `uvm_component_utils(downstream_bad_magic_test)

  function new(string name = "downstream_bad_magic_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    downstream_bad_magic_seq     cfg_seq;
    counter_verify_seq           cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting bad magic byte downstream test (DN-05)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge
    cfg_seq = downstream_bad_magic_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Build frame with correct EtherType but wrong magic (0xDE, 0xAD)
    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;

    downstream_frame_builder::build_custom_magic_frame(
      m_mem_cfg, frame_ptr, `ETHERTYPE_GATEWAY, 8'hDE, 8'hAD
    );

    // Set up RX BD
    m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

    // Step 3: Trigger ETH RX interrupt
    m_mem_cfg.vif.eth_rx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_rx_irq = 1'b0;

    // Wait for downstream FSM to read, validate (fail), and free BD
    #15us;

    // Step 4: Verify counters — 1 ETH RX, 0 CAN TX, 1 error
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = 1;
    cnt_seq.exp_can_tx = 0;
    cnt_seq.exp_errors = 1;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "DN-05 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
