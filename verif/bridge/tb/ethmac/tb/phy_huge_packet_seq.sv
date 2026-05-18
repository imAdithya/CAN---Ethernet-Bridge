// phy_huge_packet_seq.sv - Sequence for sending huge (oversized) Ethernet packets
class phy_huge_packet_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_huge_packet_seq)

  rand int num_packets;
  rand int huge_payload_size;

  constraint reasonable_packets {
    num_packets inside {[3:4]};  // Send 3-4 huge packets
  }

  constraint huge_payload {
    // Normal Ethernet max payload: 1500 bytes
    // Huge packets: 1600-2000 bytes payload  
    huge_payload_size inside {[1600:2000]};
  }

  function new(string name = "phy_huge_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    ethernet_frame_transaction req;

    `uvm_info(get_type_name(), $sformatf("Sending %0d huge packets (payload=%0d bytes)", 
              num_packets, huge_payload_size), UVM_MEDIUM)

    for (int pkt = 0; pkt < num_packets; pkt++) begin
      req = ethernet_frame_transaction::type_id::create($sformatf("huge_pkt_%0d", pkt));
      
      start_item(req);
      
      // Randomize basic fields, then set payload size manually
      assert(req.randomize() with {
        dest_addr.size() == 6;
        src_addr.size() == 6;
        dest_addr[0] == 8'hDE; dest_addr[1] == 8'hAD; dest_addr[2] == 8'hBE;
        dest_addr[3] == 8'hEF; dest_addr[4] == 8'h01; dest_addr[5] == 8'h02;
        src_addr[0] == 8'h12; src_addr[1] == 8'h34; src_addr[2] == 8'h56;
        src_addr[3] == 8'h78; src_addr[4] == 8'h9A; src_addr[5] == 8'hBC;
        type_len == 16'h0800;  // IPv4
      });
      
      // Manually set payload to huge size (payload is a queue, not dynamic array)
      req.payload.delete();
      repeat (huge_payload_size) req.payload.push_back(0);

      // Create sequential payload pattern
      foreach (req.payload[i]) begin
        req.payload[i] = (pkt * 256 + i) & 8'hFF;
      end

      finish_item(req);
      
      // Add delay between packets to allow BD processing
      #1000ns;
      
      `uvm_info(get_type_name(), $sformatf("Sent huge packet %0d/%0d (total size=%0d bytes)", 
                pkt+1, num_packets, req.payload.size() + 18), UVM_HIGH)
    end

    `uvm_info(get_type_name(), $sformatf("Completed %0d huge packets", num_packets), UVM_MEDIUM)
  endtask
endclass
