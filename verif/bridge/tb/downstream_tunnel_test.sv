// DN-06: Downstream Tunnel Mode Test
// Receives a valid tunnel Ethernet frame (EtherType=0xCABE) with correct magic bytes,
// tunnel header (seq + timestamp). Verifies CAN frame correctly extracted and
// transmitted. Confirms tunnel EtherType is accepted by VALIDATE.
class downstream_tunnel_test extends bridge_base_test;
  `uvm_component_utils(downstream_tunnel_test)

  function new(string name = "downstream_tunnel_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    downstream_tunnel_seq  cfg_seq;
    counter_verify_seq     cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  dn_data[8];

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting tunnel mode downstream test (DN-06)...", UVM_MEDIUM)
    #100ns;

    // Step 1: Configure bridge in tunnel mode
    cfg_seq = downstream_tunnel_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    // Step 2: Build a valid tunnel frame in memory
    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;
    dn_data = '{8'hA1, 8'hB2, 8'hC3, 8'hD4, 8'hE5, 8'hF6, 8'h07, 8'h08};

    downstream_frame_builder::build_tunnel_frame(
      m_mem_cfg, frame_ptr,
      .can_id(29'h1FF), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
      .data(dn_data)
    );

    // Set up RX BD
    m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd64);

    // Step 3: Trigger ETH RX interrupt
    m_mem_cfg.vif.eth_rx_irq = 1'b1;
    #40ns;
    m_mem_cfg.vif.eth_rx_irq = 1'b0;

    // Wait for downstream FSM to process
    #15us;

    // Step 4: CAN TX complete
    m_can_cfg.vif.can_tx_irq = 1'b1;
    #40ns;
    m_can_cfg.vif.can_tx_irq = 1'b0;
    #5us;

    // Step 5: Verify counters — 1 ETH RX, 1 CAN TX, 0 errors
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_eth_rx = 1;
    cnt_seq.exp_can_tx = 1;
    cnt_seq.exp_errors = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "DN-06 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
