// phy_addr_match_seq.sv - PHY sequence for address matching tests
// Sends 4 packets with different destination MAC address types
class phy_addr_match_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_addr_match_seq)

  function new(string name = "phy_addr_match_seq");
    super.new(name);
  endfunction

  virtual task body();
    // Packet 0: Matching unicast (DE:AD:BE:EF:01:02)
    send_packet('{8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01, 8'h02}, 0);
    // Packet 1: Broadcast (FF:FF:FF:FF:FF:FF)
    send_packet('{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF}, 1);
    // Packet 2: Multicast (01:00:5E:00:00:01)
    send_packet('{8'h01, 8'h00, 8'h5E, 8'h00, 8'h00, 8'h01}, 2);
    // Packet 3: Non-matching unicast (AA:BB:CC:DD:EE:FF)
    send_packet('{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF}, 3);
  endtask

  task send_packet(byte unsigned dest[6], int pkt_id);
    ethernet_frame_transaction req;
    req = ethernet_frame_transaction::type_id::create($sformatf("addr_pkt_%0d", pkt_id));
    start_item(req);

    assert(req.randomize() with {
      dest_addr.size() == 6;
      src_addr.size() == 6;
      src_addr[0] == 8'hCA; src_addr[1] == 8'hFE; src_addr[2] == 8'hBA;
      src_addr[3] == 8'hBE; src_addr[4] == 8'h00; src_addr[5] == 8'h01;
      type_len == 16'h0800;
      payload.size() == 46;
    });

    foreach (dest[i]) req.dest_addr[i] = dest[i];
    foreach (req.payload[i]) req.payload[i] = (pkt_id * 46) + i;
    req.update_fcs();
    finish_item(req);
    #1000ns;

    `uvm_info(get_type_name(), $sformatf("Sent pkt %0d dest=%02h:%02h:%02h:%02h:%02h:%02h",
              pkt_id, dest[0], dest[1], dest[2], dest[3], dest[4], dest[5]), UVM_MEDIUM)
  endtask

endclass
