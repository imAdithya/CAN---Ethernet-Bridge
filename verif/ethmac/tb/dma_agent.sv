class dma_agent extends uvm_agent;
  `uvm_component_utils(dma_agent)

  dma_agent_config m_cfg;
  dma_driver       m_driver;
  dma_sequencer    m_sequencer;
  dma_monitor      m_monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(dma_agent_config)::get(this,"","config",m_cfg))
      `uvm_fatal("DMA_AGENT","No config")

    // DRIVER + SEQUENCER ONLY IF ACTIVE
    if (m_cfg.is_active == UVM_ACTIVE) begin
      m_driver    = dma_driver::type_id::create("m_driver", this);
      m_sequencer = dma_sequencer::type_id::create("m_sequencer", this);
    end

    m_monitor = dma_monitor::type_id::create("m_monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (m_cfg.is_active == UVM_ACTIVE) begin
      m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
    end
  endfunction

endclass
