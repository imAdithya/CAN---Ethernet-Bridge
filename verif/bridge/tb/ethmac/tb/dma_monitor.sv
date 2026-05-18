class dma_monitor extends uvm_monitor;
  `uvm_component_utils(dma_monitor)

  virtual wishbone_master_if vif;
  dma_agent_config m_cfg;
  uvm_analysis_port #(wishbone_transaction) item_collected_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(dma_agent_config)::get(this, "", "config", m_cfg))
      `uvm_fatal("DMA_MON", "No dma_agent_config")
    vif = m_cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    wishbone_transaction tr;
    wishbone_transaction tr_copy;

    forever begin
      @(posedge vif.clk);

      // [CRITICAL FIX] 
      // Do not check 'vif.rst'. Rely only on 'vif.ack'.
      // If ACK is High, a transfer happened.
      #1ns;
      if (vif.ack) begin
        tr = wishbone_transaction::type_id::create("tr");

        tr.address = vif.adr;
        tr.sel     = vif.sel;
        tr.is_read = !vif.we;

        if (vif.we)
          tr.write_data = vif.dat_m;
        else
          tr.read_data  = vif.dat_s;

        tr_copy = wishbone_transaction::type_id::create("tr_copy");
        tr_copy.copy(tr);
        
        // Debug print to prove we are capturing data
        `uvm_info("DMA_MON", $sformatf("Captured DMA: Addr=0x%0h Data=0x%0h", tr.address, tr.write_data), UVM_FULL)

        item_collected_port.write(tr_copy);
      end
    end
  endtask
endclass