// tb/uvm_components/host_agent/host_driver.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class host_driver extends uvm_driver#(wishbone_transaction);
  `uvm_component_utils(host_driver)

  virtual wishbone_slave_if vif;
  host_agent_config m_config;

  function new(string name = "host_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(host_agent_config)::get(this, "", "config", m_config))
      `uvm_fatal("CONFIG_LOAD", "Cannot get config object for host_driver")
    vif = m_config.vif;
  endfunction : build_phase

  task run_phase(uvm_phase phase);
    vif.driver_cb.cyc <= 1'b0;
    vif.driver_cb.stb <= 1'b0;
    vif.driver_cb.we  <= 1'b0;

    forever begin
      seq_item_port.get_next_item(req); // Get the request from the sequencer
      `uvm_info("HOST_DRIVER", "Driving new WISHBONE transaction", UVM_MEDIUM)
      
      drive_one_transaction(req); // Execute the physical transaction

      // FIX: Send the transaction (now containing read_data) back to the sequence.
      seq_item_port.item_done();
      seq_item_port.put_response(req);
    end
  endtask : run_phase

  protected virtual task drive_one_transaction(wishbone_transaction txn);
    int timeout;
    
    // Drive bus request
    @(posedge vif.clk);
    vif.driver_cb.adr   <= txn.address;
    vif.driver_cb.we    <= !txn.is_read;
    vif.driver_cb.dat_m <= txn.write_data;
    vif.driver_cb.cyc   <= 1'b1;
    vif.driver_cb.stb   <= 1'b1;

    // [CRITICAL FIX 1] Handle uninitialized Byte Selects
    // If the sequence sent sel=0, force it to 0xF (32-bit access)
    if (txn.sel == 4'b0000)
      vif.driver_cb.sel <= 4'b1111; 
    else
      vif.driver_cb.sel <= txn.sel;

    //  DEBUG: show what we just placed on the bus
    if (txn.is_read)
      `uvm_info("HOST_DRIVER", $sformatf("READ start  addr=0x%0h", txn.address), UVM_HIGH)
    else
      `uvm_info("HOST_DRIVER", $sformatf("WRITE start addr=0x%0h data=0x%0h", txn.address, txn.write_data), UVM_LOW)

    // Wait for ACK/ERR
    timeout = 1000;
    // Wait until ACK goes high. The data is valid ON THIS CYCLE.
    while (!(vif.ack || vif.err) && timeout--) @(posedge vif.clk);
    
    if (timeout <= 0) begin
      `uvm_error("HOST_DRIVER", $sformatf("Timeout waiting for ACK @0x%0h", txn.address))
      vif.driver_cb.cyc <= 1'b0;
      vif.driver_cb.stb <= 1'b0;
      return;
    end

    // Capture read data
    if (txn.is_read) begin
      // [CRITICAL FIX 2] Remove the extra clock cycle delay!
      // Standard Wishbone: Data is valid when ACK is high.
      // If you wait one more clock (@posedge), the slave might have already removed the data.
      txn.read_data = vif.dat_s; 
      
      `uvm_info("HOST_DRIVER", $sformatf("READ done   addr=0x%0h -> data=0x%0h",
               txn.address, txn.read_data), UVM_HIGH)
    end

    // Deassert handshake (Pipeline approach: clear immediately after ACK)
    vif.driver_cb.cyc <= 1'b0;
    vif.driver_cb.stb <= 1'b0;
    
    // Insert idle cycle and clear lines
    @(posedge vif.clk);
    vif.driver_cb.adr   <= '0;
    vif.driver_cb.dat_m <= '0;
    vif.driver_cb.sel   <= '0;
    vif.driver_cb.we    <= 1'b0;

    //  DEBUG: end of write
    if (!txn.is_read)
      `uvm_info("HOST_DRIVER", $sformatf("WRITE done  addr=0x%0h data=0x%0h",
               txn.address, txn.write_data), UVM_LOW)
  endtask : drive_one_transaction


endclass : host_driver