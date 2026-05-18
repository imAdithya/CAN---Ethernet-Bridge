// phy_promisc_seq.sv - PHY sequence for promiscuous mode testing
// Sends packets with varied destination MAC addresses
class phy_promisc_seq extends uvm_sequence #(ethernet_frame_transaction);
  `uvm_object_utils(phy_promisc_seq)

  // Mode: 0 = mixed (unicast-match, unicast-miss, broadcast, multicast)
  //       1 = all non-matching unicast
  int mode;

  function new(string name = "phy_promisc_seq");
    super.new(name);
    mode = 0;
  endfunction

  virtual task body();
    ethernet_frame_transaction req;

    if (mode == 0) begin
      send_mixed_packets();
    end else begin
      send_nonmatching_packets();
    end
  endtask

  // Mode 0: Send 4 packets with different dest MACs
  task send_mixed_packets();
    ethernet_frame_transaction req;
    byte unsigned dest_macs[4][6];

    // Packet 0: Matching unicast (DE:AD:BE:EF:01:02)
    dest_macs[0] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01, 8'h02};
    // Packet 1: Non-matching unicast (AA:BB:CC:DD:EE:FF)
    dest_macs[1] = '{8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF};
    // Packet 2: Broadcast (FF:FF:FF:FF:FF:FF)
    dest_macs[2] = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
    // Packet 3: Multicast (01:00:5E:00:00:01)
    dest_macs[3] = '{8'h01, 8'h00, 8'h5E, 8'h00, 8'h00, 8'h01};

    `uvm_info(get_type_name(), "Sending 4 mixed-MAC packets", UVM_MEDIUM)

    for (int pkt = 0; pkt < 4; pkt++) begin
      req = ethernet_frame_transaction::type_id::create($sformatf("promisc_pkt_%0d", pkt));
      start_item(req);

      assert(req.randomize() with {
        dest_addr.size() == 6;
        src_addr.size() == 6;
        src_addr[0] == 8'hCA; src_addr[1] == 8'hFE; src_addr[2] == 8'hBA;
        src_addr[3] == 8'hBE; src_addr[4] == 8'h00; src_addr[5] == 8'h01;
        type_len == 16'h0800;
        payload.size() == 46;
      });

      // Override dest MAC
      for (int i = 0; i < 6; i++) req.dest_addr[i] = dest_macs[pkt][i];

      // Unique payload pattern
      foreach (req.payload[i]) req.payload[i] = (pkt * 46) + i;

      req.update_fcs();
      finish_item(req);
      #1000ns;

      `uvm_info(get_type_name(), $sformatf("Sent mixed pkt %0d/4 dest=%02h:%02h:%02h:%02h:%02h:%02h",
                pkt+1, dest_macs[pkt][0], dest_macs[pkt][1], dest_macs[pkt][2],
                dest_macs[pkt][3], dest_macs[pkt][4], dest_macs[pkt][5]), UVM_MEDIUM)
    end
  endtask

  // Mode 1: Send 4 packets all with non-matching unicast dest MAC
  task send_nonmatching_packets();
    ethernet_frame_transaction req;

    `uvm_info(get_type_name(), "Sending 4 non-matching unicast packets", UVM_MEDIUM)

    for (int pkt = 0; pkt < 4; pkt++) begin
      req = ethernet_frame_transaction::type_id::create($sformatf("promisc_nm_pkt_%0d", pkt));
      start_item(req);

      assert(req.randomize() with {
        dest_addr.size() == 6;
        src_addr.size() == 6;
        dest_addr[0] == 8'h10; dest_addr[1] == 8'h20; dest_addr[2] == 8'h30;
        src_addr[0] == 8'hCA; src_addr[1] == 8'hFE; src_addr[2] == 8'hBA;
        src_addr[3] == 8'hBE; src_addr[4] == 8'h00; src_addr[5] == 8'h01;
        type_len == 16'h0800;
        payload.size() == 46;
      });

      // Unique non-matching dest per packet
      req.dest_addr[3] = 8'h40 + pkt;
      req.dest_addr[4] = 8'h50;
      req.dest_addr[5] = 8'h60 + pkt;

      // Unique payload
      foreach (req.payload[i]) req.payload[i] = (pkt * 46) + i + 128;

      req.update_fcs();
      finish_item(req);
      #1000ns;

      `uvm_info(get_type_name(), $sformatf("Sent non-matching pkt %0d/4", pkt+1), UVM_MEDIUM)
    end
  endtask

endclass
