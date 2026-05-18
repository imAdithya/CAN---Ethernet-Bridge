// tb/uvm_components/host_agent/host_monitor.sv
`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ethmac_defines.v"

class host_monitor extends uvm_monitor;
  `uvm_component_utils(host_monitor)

  virtual wishbone_slave_if  vif;
  virtual wishbone_master_if mem_vif;
  
  host_agent_config m_config;

  uvm_analysis_port #(wishbone_transaction) item_collected_port;

  protected int local_tx_bd_num;

  function new(string name = "host_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(host_agent_config)::get(this, "", "config", m_config))
      `uvm_fatal("CONFIG_LOAD", "Cannot get config object for host_monitor")
    
    vif = m_config.vif;
    mem_vif = m_config.mem_vif;

    local_tx_bd_num = `ETH_TX_BD_NUM_DEF_0;
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    fork
      monitor_slave_port();
      monitor_master_port();
    join
  endtask : run_phase

  protected virtual task monitor_slave_port();
  wishbone_transaction txn;
  wishbone_transaction txn_clone; // Handle for the clone

  forever begin
    @(vif.monitor_cb);
    if (vif.monitor_cb.cyc && vif.monitor_cb.stb) begin
      txn = wishbone_transaction::type_id::create("txn");

      txn.is_read    = !vif.monitor_cb.we;
      txn.address = vif.monitor_cb.adr; // convert byte to word address
      txn.sel        = vif.monitor_cb.sel;
      txn.is_dma_txn = 0;

      if (!txn.is_read) begin
        txn.write_data = vif.monitor_cb.dat_m;
        if (txn.address == `ETH_TX_BD_NUM_ADR) begin
          local_tx_bd_num = txn.write_data[7:0];
          //`uvm_info("HOST_MON_SLAVE", $sformatf("Captured TX_BD_NUM write. New value: %0d", local_tx_bd_num), UVM_MEDIUM)
        end
      end

      wait(vif.monitor_cb.ack || vif.monitor_cb.err);

      if (txn.is_read)
        txn.read_data = vif.monitor_cb.dat_s;

      if (txn.address >= 'h400 && txn.address <= 'h7ff)
        txn.is_bd = 1;

      // Clone before writing
      $cast(txn_clone, txn.clone());
      item_collected_port.write(txn_clone);
    end
  end
endtask : monitor_slave_port


  protected virtual task monitor_master_port();
    wishbone_transaction txn;
    wishbone_transaction txn_clone; // Handle for the clone
    int tx_bd_boundary_addr; 
    
    forever begin
      @(mem_vif.monitor_cb);
      if (mem_vif.monitor_cb.cyc && mem_vif.monitor_cb.stb) begin
        txn = wishbone_transaction::type_id::create("txn");

        txn.is_read    = !mem_vif.monitor_cb.we;
        txn.address = mem_vif.monitor_cb.adr;
        txn.sel        = mem_vif.monitor_cb.sel;
        txn.is_dma_txn = 1;
        
        if (!txn.is_read) begin
          txn.write_data = mem_vif.monitor_cb.dat_m;
        end
        
        wait(mem_vif.monitor_cb.ack || mem_vif.monitor_cb.err);
        
        if (txn.is_read) begin
          txn.read_data = mem_vif.monitor_cb.dat_s;
        end

        if (txn.address >= 'h400 && txn.address <= 'h7ff) begin
            txn.is_bd = 1;
            
            tx_bd_boundary_addr = 'h400 + (local_tx_bd_num * 8);
            
            if (txn.address < tx_bd_boundary_addr) begin
                txn.is_tx_bd = 1;
            end else begin
                txn.is_rx_bd = 1;
            end
        end

        // FIX: Clone the transaction before sending it
        $cast(txn_clone, txn.clone());
        item_collected_port.write(txn_clone);
      end
    end
  endtask : monitor_master_port

endclass : host_monitor