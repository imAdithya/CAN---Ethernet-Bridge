class dma_driver extends uvm_driver #(wishbone_transaction);
  `uvm_component_utils(dma_driver)

  dma_agent_config m_cfg;
  virtual wishbone_master_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

function void build_phase(uvm_phase phase);
  super.build_phase(phase);

  if (!uvm_config_db#(dma_agent_config)::get(
        this, "", "config", m_cfg))
    `uvm_fatal("DMA_DRV", "No dma_agent_config")

  vif = m_cfg.vif;
endfunction


  task run_phase(uvm_phase phase);
    wishbone_transaction tr;

    forever begin
      seq_item_port.get_next_item(tr);

      // ---------------- WRITE ----------------
      if (!tr.is_read) begin
        vif.cyc <= 1;
        vif.stb <= 1;
        vif.we  <= 1;
        vif.adr <= tr.address;
        vif.dat_m <= tr.write_data;
        vif.sel <= tr.sel;

        @(posedge vif.clk);
        wait (vif.ack);

        vif.cyc <= 0;
        vif.stb <= 0;
        vif.we  <= 0;
      end

      // ---------------- READ ----------------
      else begin
        vif.cyc <= 1;
        vif.stb <= 1;
        vif.we  <= 0;
        vif.adr <= tr.address;
        vif.sel <= tr.sel;

        @(posedge vif.clk);
        wait (vif.ack);

        tr.read_data = vif.dat_s;

        vif.cyc <= 0;
        vif.stb <= 0;
      end

      seq_item_port.item_done();
    end
  endtask

endclass
