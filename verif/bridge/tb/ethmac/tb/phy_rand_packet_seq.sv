// phy_rand_packet_seq.sv - Randomized Packet Sequence with Various Address Types
class phy_rand_packet_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_rand_packet_seq)

  rand int num_packets;  // Number of packets to send
  rand int payload_size_min;
  rand int payload_size_max;

  // MAC address patterns
  byte unsigned unicast_mac[6]   = '{8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07}; // Our MAC
  byte unsigned multicast_mac[6] = '{8'h01, 8'h00, 8'h5E, 8'h00, 8'h00, 8'h01}; // IPv4 multicast
  byte unsigned broadcast_mac[6] = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF}; // Broadcast
  byte unsigned wrong_mac[6]     = '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF}; // Different unicast

  typedef enum {UNICAST, MULTICAST, BROADCAST, WRONG_UNICAST} addr_type_e;

  constraint reasonable_config {
    num_packets inside {[5:10]};
    payload_size_min inside {[46:100]};    // Minimum Ethernet payload
    payload_size_max inside {[100:1500]};  // Up to maximum
    payload_size_min < payload_size_max;
  }

  function new(string name = "phy_rand_packet_seq");
    super.new(name);
  endfunction

  virtual task body();
    ethernet_frame_transaction req;
    int pkt_size;
    int byte_offset = 0;

    `uvm_info(get_type_name(), $sformatf("Sending %0d randomized packets with mixed address types", num_packets), UVM_MEDIUM)

    for (int pkt = 0; pkt < num_packets; pkt++) begin
      req = ethernet_frame_transaction::type_id::create($sformatf("rand_pkt_%0d", pkt));
      
      // Randomize payload size for each packet
      pkt_size = $urandom_range(payload_size_min, payload_size_max);
      
      start_item(req);
      
      // Randomize packet with different address types
      assert(req.randomize() with {
        dest_addr.size() == 6;
        src_addr.size() == 6;
        src_addr[0] == 8'h12; src_addr[1] == 8'h34; src_addr[2] == 8'h56;
        src_addr[3] == 8'h78; src_addr[4] == 8'h9A; src_addr[5] == 8'hBC;
        type_len == 16'h0800;
        payload.size() == pkt_size;
      });

      // Assign destination address based on packet number to test filtering
      case (pkt % 4)
        0, 1: begin  // 50% unicast to our MAC (should be accepted)
          req.dest_addr = '{8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07};
        end
        2: begin  // 25% broadcast (accepted with BRO=1)
          req.dest_addr = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
        end
        3: begin  // 25% multicast (should be rejected) - LSB of first byte = 1
          req.dest_addr = '{8'hAB, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF};
        end
      endcase

      // Sequential payload pattern
      foreach (req.payload[i]) begin
        req.payload[i] = (byte_offset + i) & 8'hFF;
      end

      `uvm_info(get_type_name(), $sformatf("Pkt %0d: size=%0d bytes, dest=%02x:%02x:%02x:%02x:%02x:%02x", 
                pkt, pkt_size + 18, req.dest_addr[0], req.dest_addr[1], req.dest_addr[2],
                req.dest_addr[3], req.dest_addr[4], req.dest_addr[5]), UVM_HIGH)

      finish_item(req);
      
     // Add delay between packets to allow BD reset and processing
      #1000ns;
      
      // Update offset for next packet
      byte_offset += pkt_size;
    end

    `uvm_info(get_type_name(), $sformatf("Completed %0d randomized packets (unicast/broadcast/other mix)", num_packets), UVM_MEDIUM)
  endtask
endclass
