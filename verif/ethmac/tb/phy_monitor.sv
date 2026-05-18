// tb/uvm_components/phy_agent/phy_monitor.sv
`include "uvm_macros.svh"
import uvm_pkg::*;

class phy_monitor extends uvm_monitor;
  `uvm_component_utils(phy_monitor)

  // Virtual interface handle
  virtual mii_if vif;
  phy_agent_config m_config;

  // Analysis port to broadcast collected transactions
  uvm_analysis_port #(ethernet_frame_transaction) item_collected_port;

  //-------------------------------------------------------------------------
  // Constructor
  //-------------------------------------------------------------------------
  function new(string name = "phy_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  //-------------------------------------------------------------------------
  // Build Phase
  //-------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(phy_agent_config)::get(this, "", "config", m_config))
      `uvm_fatal("CONFIG_LOAD", "Cannot get config object for phy_monitor")
    vif = m_config.vif;
  endfunction : build_phase

  //-------------------------------------------------------------------------
  // Run Phase
  //-------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    ethernet_frame_transaction txn;
    logic [7:0] current_byte;
    logic       is_upper_nibble;
    int         byte_count;

    forever begin
      // 1. Wait for Start of Frame (RX_DV High)
      @(posedge vif.mon_cb.rx_dv);
      
      `uvm_info("PHY_MONITOR", "Detected RX frame start", UVM_HIGH);

      txn = ethernet_frame_transaction::type_id::create("txn");
      is_upper_nibble = 0;
      byte_count = 0;

      // Capture nibbles while rx_dv is high
      while (vif.mon_cb.rx_dv) begin
        // Sample CURRENT nibble first, then wait for next clock
        if (!is_upper_nibble) begin
          // Capture Lower Nibble (LSB first in MII)
          current_byte[3:0] = vif.mon_cb.rxd;
          is_upper_nibble = 1;
        end
        else begin
          // Capture Upper Nibble (MSB second in MII)
          current_byte[7:4] = vif.mon_cb.rxd;
          is_upper_nibble = 0;

          // 3. Process Byte (Skip Preamble+SFD = 8 bytes)
          if (byte_count >= 8) begin 
            int effective_count = byte_count - 8;
            
            // Fill Transaction Fields
            if (effective_count < 6) 
                 txn.dest_addr[effective_count] = current_byte;
            else if (effective_count < 12)
                 txn.src_addr[effective_count - 6] = current_byte;
            else if (effective_count < 14)
                 txn.type_len = (txn.type_len << 8) | current_byte;
            else
                 txn.payload.push_back(current_byte);
          end
          byte_count++;
        end
        
        // Wait for next clock cycle to get next nibble
        @(vif.mon_cb);
      end


      `uvm_info("PHY_MONITOR", $sformatf("Detected RX frame end. Payload size: %0d", txn.payload.size()), UVM_MEDIUM);

      // DEBUG: Print first 20 bytes captured
      begin
        string captured_str = "PHY CAPTURED[0:19]: ";
        captured_str = $sformatf("%scapPHY dest=%02x:%02x:%02x:%02x:%02x:%02x src=%02x:%02x:%02x:%02x:%02x:%02x type=%04x payload[0:5]=%02x %02x %02x %02x %02x %02x",
          captured_str,
          txn.dest_addr[0], txn.dest_addr[1], txn.dest_addr[2], txn.dest_addr[3], txn.dest_addr[4], txn.dest_addr[5],
          txn.src_addr[0], txn.src_addr[1], txn.src_addr[2], txn.src_addr[3], txn.src_addr[4], txn.src_addr[5],
          txn.type_len,
          txn.payload.size() > 0 ? txn.payload[0] : 8'h00,
          txn.payload.size() > 1 ? txn.payload[1] : 8'h00,
          txn.payload.size() > 2 ? txn.payload[2] : 8'h00,
          txn.payload.size() > 3 ? txn.payload[3] : 8'h00,
          txn.payload.size() > 4 ? txn.payload[4] : 8'h00,
          txn.payload.size() > 5 ? txn.payload[5] : 8'h00
        );
        `uvm_info("PHY_DEBUG", captured_str, UVM_LOW)
      end

      // 4. Extract FCS (Last 4 Bytes)
      // CRC is transmitted LSB-first, so pop_back gives us bytes in reverse
      // After shifting and ORing, we get the correct 32-bit value
      if (txn.payload.size() >= 4) begin
        for (int i = 0; i < 4; i++) begin
            txn.fcs = (txn.fcs << 8) | txn.payload.pop_back();
        end
        // No byte reversal needed - pop_back + shifting gives correct value already
      end
      
      // Send to Scoreboard
      item_collected_port.write(txn);
    end
  endtask : run_phase

endclass : phy_monitor