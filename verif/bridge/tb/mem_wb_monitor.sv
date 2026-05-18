// mem_wb_monitor.sv — Monitors ETH/RAM WB bus transactions
// Detects BD programming and frame writes to reconstruct bridge frames

class mem_wb_monitor extends uvm_monitor;
  `uvm_component_utils(mem_wb_monitor)

  virtual mem_wb_if.Monitor vif;
  mem_wb_agent_config cfg;

  uvm_analysis_port #(bridge_wb_transaction) item_collected_port;

  function new(string name = "mem_wb_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mem_wb_agent_config)::get(this, "", "config", cfg))
      `uvm_fatal("CFG", "Cannot get mem_wb_agent_config")
    vif = cfg.vif;
  endfunction

  task run_phase(uvm_phase phase);
    bridge_wb_transaction txn;

    forever begin
      @(posedge vif.clk iff (vif.cyc && vif.stb && vif.ack));

      txn = bridge_wb_transaction::type_id::create("mem_wb_txn");
      txn.address    = vif.adr;
      txn.is_read    = !vif.we;
      txn.write_data = vif.dat_m;
      txn.read_data  = vif.dat_s;
      txn.sel        = vif.sel;
      txn.is_can_bus = 0;

      `uvm_info("MEM_MON", $sformatf("%s [0x%08h] = 0x%08h",
                txn.is_read ? "RD" : "WR", txn.address,
                txn.is_read ? txn.read_data : txn.write_data), UVM_HIGH)

      item_collected_port.write(txn);
    end
  endtask
endclass
