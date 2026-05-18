// SYS-04: Full Duplex Stress Test
// Sustained bidirectional traffic: multiple upstream + downstream frames.
// Verifies zero frame loss and counter consistency.
class sys_fullduplex_stress_test extends bridge_base_test;
  `uvm_component_utils(sys_fullduplex_stress_test)

  function new(string name = "sys_fullduplex_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    sys_fullduplex_stress_seq cfg_seq;
    counter_verify_seq        cnt_seq;
    bit [31:0] rx_bd_addr, frame_ptr;
    bit [7:0]  dn_data[8];
    int num_frames;

    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Starting full-duplex stress test (SYS-04)...", UVM_MEDIUM)
    #100ns;

    cfg_seq = sys_fullduplex_stress_seq::type_id::create("cfg_seq");
    cfg_seq.start(m_env.m_host_agent.m_sequencer);

    rx_bd_addr = `DEFAULT_RX_BD_ADDR;
    frame_ptr  = rx_bd_addr + 32'h100;
    num_frames = 5;

    // Alternate upstream and downstream frames
    for (int f = 0; f < num_frames; f++) begin
      `uvm_info("SYS04", $sformatf("--- Round %0d ---", f), UVM_MEDIUM)

      // --- Upstream frame ---
      m_can_cfg.load_can_frame(
        .can_id(29'h100 + f), .dlc(4'd4), .eff(1'b0), .rtr(1'b0),
        .data('{8'h10+f, 8'h20+f, 8'h30+f, 8'h40+f, 8'h00, 8'h00, 8'h00, 8'h00})
      );

      m_can_cfg.vif.can_rx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_rx_irq = 1'b0;
      #10us;

      m_mem_cfg.vif.eth_tx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_tx_irq = 1'b0;
      #2us;

      // --- Downstream frame ---
      for (int i = 0; i < 8; i++)
        dn_data[i] = f * 16 + i;

      downstream_frame_builder::build_gateway_frame(
        m_mem_cfg, frame_ptr,
        .can_id(29'h200 + f), .dlc(4'd8), .eff(1'b0), .rtr(1'b0),
        .data(dn_data)
      );
      m_mem_cfg.setup_rx_bd(rx_bd_addr, frame_ptr, 16'd60);

      m_mem_cfg.vif.eth_rx_irq = 1'b1;
      #40ns;
      m_mem_cfg.vif.eth_rx_irq = 1'b0;
      #15us;

      m_can_cfg.vif.can_tx_irq = 1'b1;
      #40ns;
      m_can_cfg.vif.can_tx_irq = 1'b0;
      #5us;
    end

    // Verify counter consistency
    cnt_seq = counter_verify_seq::type_id::create("cnt_seq");
    cnt_seq.exp_can_rx   = num_frames;
    cnt_seq.exp_eth_tx   = num_frames;
    cnt_seq.exp_eth_rx   = num_frames;
    cnt_seq.exp_can_tx   = num_frames;
    cnt_seq.exp_filtered = 0;
    cnt_seq.exp_errors   = 0;
    cnt_seq.start(m_env.m_host_agent.m_sequencer);

    #500ns;
    `uvm_info(get_type_name(), "SYS-04 finished.", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass
