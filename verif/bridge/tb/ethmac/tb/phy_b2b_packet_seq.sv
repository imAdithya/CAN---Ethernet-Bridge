// phy_b2b_packet_seq.sv - Back-to-Back Packet Sequence
class phy_b2b_packet_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_b2b_packet_seq)

  rand int num_packets;  // Number of back-to-back packets to send

  constraint reasonable_packets {
    num_packets inside {[3:5]};  // Send 3-5 packets back-to-back
  }

  function new(string name = "phy_b2b_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    ethernet_frame_transaction req;

    `uvm_info(get_type_name(), $sformatf("Sending %0d back-to-back packets", num_packets), UVM_MEDIUM)

    for (int pkt = 0; pkt < num_packets; pkt++) begin
      req = ethernet_frame_transaction::type_id::create($sformatf("b2b_pkt_%0d", pkt));
      
      start_item(req);
      
      // Randomize packet with unique pattern for each packet
      assert(req.randomize() with {
        dest_addr.size() == 6;
        src_addr.size() == 6;
        dest_addr[0] == 8'hA0; dest_addr[1] == 8'hB1; dest_addr[2] == 8'hC2;
        dest_addr[3] == 8'hD3; dest_addr[4] == 8'hE4; dest_addr[5] == 8'hF5;
        src_addr[0] == 8'hCA; src_addr[1] == 8'hFE; src_addr[2] == 8'hBA;
        src_addr[3] == 8'hBE; src_addr[4] == 8'h00; src_addr[5] == 8'h01;
        type_len == 16'h0800;
        payload.size() == 46;  // Minimum payload for 64-byte frame
      });

      // Create unique payload pattern for each packet
      foreach (req.payload[i]) begin
        req.payload[i] = (pkt * 46) + i;  // Sequential pattern unique per packet
      end

      finish_item(req);
      
      // Add delay between packets to allow BD reset and processing
      // Without this, packets arrive faster than MAC can process them
      #1000ns;
      
      `uvm_info(get_type_name(), $sformatf("Sent packet %0d/%0d", pkt+1, num_packets), UVM_HIGH)
    end

    `uvm_info(get_type_name(), $sformatf("Completed %0d back-to-back packets", num_packets), UVM_MEDIUM)
  endtask
endclass
