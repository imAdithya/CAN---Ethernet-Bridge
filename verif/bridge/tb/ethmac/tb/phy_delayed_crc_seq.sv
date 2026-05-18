// phy_delayed_crc_seq.sv - PHY sequence for delayed CRC testing
// Sends normal-sized packets to DEAD:BEEF:01:02 MAC address
class phy_delayed_crc_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_delayed_crc_seq)

  rand int num_packets;  // Number of packets to send

  constraint reasonable_packets {
    num_packets inside {[4:5]};  // Send 4-5 packets
  }

  function new(string name = "phy_delayed_crc_seq");
    super.new(name);
  endfunction

  virtual task body();
    ethernet_frame_transaction req;

    `uvm_info(get_type_name(), $sformatf("Sending %0d packets for delayed CRC test", num_packets), UVM_MEDIUM)

    for (int pkt = 0; pkt < num_packets; pkt++) begin
      req = ethernet_frame_transaction::type_id::create($sformatf("dlycrc_pkt_%0d", pkt));
      
      start_item(req);
      
      // Send to DEAD:BEEF:01:02 MAC address (matches delayed_crc_rx_seq config)
      assert(req.randomize() with {
        dest_addr.size() == 6;
        src_addr.size() == 6;
        dest_addr[0] == 8'hDE; dest_addr[1] == 8'hAD; dest_addr[2] == 8'hBE;
        dest_addr[3] == 8'hEF; dest_addr[4] == 8'h01; dest_addr[5] == 8'h02;
        src_addr[0] == 8'hCA; src_addr[1] == 8'hFE; src_addr[2] == 8'hBA;
        src_addr[3] == 8'hBE; src_addr[4] == 8'h00; src_addr[5] == 8'h01;
        type_len == 16'h0800;  // IPv4
        payload.size() == 46;  // Minimum payload for 64-byte frame
      });

      // Create unique payload pattern for each packet
      foreach (req.payload[i]) begin
        req.payload[i] = (pkt * 46) + i;  // Sequential pattern unique per packet
      end

      req.update_fcs(); // Recompute CRC after payload override

      finish_item(req);
      
      // Add delay between packets
      #1000ns;
      
      `uvm_info(get_type_name(), $sformatf("Sent packet %0d/%0d to DEAD:BEEF:01:02", pkt+1, num_packets), UVM_HIGH)
    end

    `uvm_info(get_type_name(), $sformatf("Completed %0d packets for delayed CRC test", num_packets), UVM_MEDIUM)
  endtask
endclass
