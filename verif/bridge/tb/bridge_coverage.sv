// bridge_coverage.sv — Functional coverage for the CAN-Ethernet Bridge
// Follows the same pattern as eth_coverage.sv (uvm_subscriber)
// Samples bridge register writes, FSM states, and datapath signals.


class bridge_coverage extends uvm_subscriber #(wishbone_transaction);
  `uvm_component_utils(bridge_coverage)

  // =========================================================================
  // Internal state for coverage sampling
  // =========================================================================
  logic [31:0] cov_addr;
  logic [31:0] cov_data;
  bit          cov_is_read;

  // Bridge register state
  logic [31:0] bridge_ctrl_val;
  logic [31:0] filter_ctrl_val;
  logic [31:0] dst_mac_hi_val, src_mac_hi_val;

  // FSM state (sampled via hierarchical reference or interface)
  logic [3:0]  up_fsm_state;
  logic [3:0]  dn_fsm_state;

  // Upstream datapath
  logic [28:0] up_can_id;
  logic [3:0]  up_can_dlc;
  bit          up_can_eff;
  bit          up_can_rtr;
  bit          up_filter_drop;

  // Downstream datapath
  logic [15:0] dn_ethertype;
  logic [3:0]  dn_can_dlc;
  bit          dn_frame_valid;
  logic [3:0]  dn_queue_depth;

  // Arbiter
  bit          can_bus_contention;
  bit          eth_bus_contention;

  // Counters read
  logic [31:0] cnt_can_rx_val, cnt_eth_tx_val;
  logic [31:0] cnt_eth_rx_val, cnt_can_tx_val;
  logic [31:0] cnt_filtered_val, cnt_errors_val;

  // =========================================================================
  // CG1: Bridge Register Address Coverage (REG-01)
  // =========================================================================
  covergroup reg_addr_cg;
    option.per_instance = 1;
    option.name = "bridge_reg_addr_cg";

    cp_addr: coverpoint cov_addr {
      bins bridge_ctrl  = {`REG_BRIDGE_CTRL};
      bins bridge_stat  = {`REG_BRIDGE_STATUS};
      bins dst_mac_hi   = {`REG_DST_MAC_HI};
      bins dst_mac_lo   = {`REG_DST_MAC_LO};
      bins src_mac_hi   = {`REG_SRC_MAC_HI};
      bins src_mac_lo   = {`REG_SRC_MAC_LO};
      bins filter_ctrl  = {`REG_FILTER_CTRL};
      bins cnt_can_rx   = {`REG_CNT_CAN_RX};
      bins cnt_eth_tx   = {`REG_CNT_ETH_TX};
      bins cnt_eth_rx   = {`REG_CNT_ETH_RX};
      bins cnt_can_tx   = {`REG_CNT_CAN_TX};
      bins cnt_filtered = {`REG_CNT_FILTERED};
      bins cnt_errors   = {`REG_CNT_ERRORS};
      bins tunnel_seq   = {`REG_TUNNEL_SEQ};
      bins tx_bd_addr   = {`REG_TX_BD_ADDR};
      bins rx_bd_addr   = {`REG_RX_BD_ADDR};
      bins filter_tbl   = {[`REG_FILTER_TBL_BASE:`REG_FILTER_TBL_END]};
    }

    cp_access: coverpoint cov_is_read {
      bins read  = {1};
      bins write = {0};
    }

    cross_addr_access: cross cp_addr, cp_access {
      ignore_bins ro_write =
        binsof(cp_access.write) && (
          binsof(cp_addr.bridge_stat) ||
          binsof(cp_addr.cnt_can_rx)  || binsof(cp_addr.cnt_eth_tx) ||
          binsof(cp_addr.cnt_eth_rx)  || binsof(cp_addr.cnt_can_tx) ||
          binsof(cp_addr.cnt_filtered)|| binsof(cp_addr.cnt_errors) ||
          binsof(cp_addr.tunnel_seq)
        );
    }
  endgroup

  // =========================================================================
  // CG2: Register Data Pattern Coverage (REG-01)
  // =========================================================================
  covergroup reg_data_cg;
    option.per_instance = 1;
    option.name = "bridge_reg_data_cg";

    cp_data: coverpoint cov_data {
      bins all_zeros  = {32'h0000_0000};
      bins all_ones   = {32'hFFFF_FFFF};
      bins low_byte   = {[32'h0000_0001:32'h0000_00FF]};
      bins low_word   = {[32'h0000_0100:32'h0000_FFFF]};
      bins upper_bits = {[32'h0001_0000:32'hFFFF_FFFE]};
    }
  endgroup

  // =========================================================================
  // CG3: Reset Default Coverage (REG-02)
  // =========================================================================
  covergroup reg_reset_cg;
    option.per_instance = 1;
    option.name = "bridge_reg_reset_cg";

    cp_reset_reg: coverpoint cov_addr {
      bins bridge_ctrl = {`REG_BRIDGE_CTRL};
      bins dst_mac_hi  = {`REG_DST_MAC_HI};
      bins dst_mac_lo  = {`REG_DST_MAC_LO};
      bins src_mac_hi  = {`REG_SRC_MAC_HI};
      bins src_mac_lo  = {`REG_SRC_MAC_LO};
      bins filter_ctrl = {`REG_FILTER_CTRL};
      bins tx_bd_addr  = {`REG_TX_BD_ADDR};
      bins rx_bd_addr  = {`REG_RX_BD_ADDR};
    }

    cp_is_read: coverpoint cov_is_read {
      bins read = {1};
    }

    cross_reset_read: cross cp_reset_reg, cp_is_read;
  endgroup

  // =========================================================================
  // CG4: Bridge Mode Coverage (MODE-01, MODE-02)
  // =========================================================================
  covergroup bridge_mode_cg;
    option.per_instance = 1;
    option.name = "bridge_mode_cg";

    cp_enable: coverpoint bridge_ctrl_val[0] {
      bins disabled = {0};  // MODE-02
      bins enabled  = {1};  // all other tests
    }

    cp_mode: coverpoint bridge_ctrl_val[2:1] {
      bins gateway = {2'b01};  // UP-01..03,05, DN-01..04
      bins tunnel  = {2'b10};  // UP-04, DN-02
    }

    cross_en_mode: cross cp_enable, cp_mode;
  endgroup

  // =========================================================================
  // CG5: Filter Configuration Coverage (FLT-01, FLT-02)
  // =========================================================================
  covergroup filter_config_cg;
    option.per_instance = 1;
    option.name = "filter_config_cg";

    cp_filter_en: coverpoint filter_ctrl_val[0] {
      bins disabled = {0};  // FLT-03 (filter off)
      bins enabled  = {1};  // FLT-01, FLT-02
    }

    cp_filter_mode: coverpoint filter_ctrl_val[1] {
      bins accept_list = {0};  // FLT-01
      bins reject_list = {1};  // FLT-02
    }

    cross_filter: cross cp_filter_en, cp_filter_mode {
      ignore_bins disabled_mode = binsof(cp_filter_en.disabled);
    }
  endgroup

  // =========================================================================
  // CG6: Filter Result Coverage (FLT-01, FLT-02, UP-05)
  // =========================================================================
  covergroup filter_result_cg;
    option.per_instance = 1;
    option.name = "filter_result_cg";

    cp_drop: coverpoint up_filter_drop {
      bins pass = {0};  // FLT-01 match, FLT-02 no-match
      bins drop = {1};  // FLT-01 no-match, FLT-02 match, UP-05
    }
  endgroup

  // =========================================================================
  // CG7: Upstream FSM State Coverage (UP-01..05, SYS-01)
  // =========================================================================
  covergroup up_fsm_cg;
    option.per_instance = 1;
    option.name = "up_fsm_cg";

    cp_state: coverpoint up_fsm_state {
      bins idle      = {`UP_IDLE};
      bins read_can  = {`UP_READ_CAN};
      bins filter    = {`UP_FILTER};
      bins encap     = {`UP_ENCAP};
      bins write_ram = {`UP_WRITE_RAM};
      bins prog_bd   = {`UP_PROG_BD};
      bins wait_tx   = {`UP_WAIT_TX};
      bins release_s = {`UP_RELEASE};
    }
  endgroup

  // =========================================================================
  // CG8: Upstream CAN Frame Coverage (UP-01..04)
  // =========================================================================
  covergroup up_can_frame_cg;
    option.per_instance = 1;
    option.name = "up_can_frame_cg";

    cp_dlc: coverpoint up_can_dlc {
      bins dlc_0 = {0};   // UP-03 boundary
      bins dlc_1 = {1};
      bins dlc_2 = {2};
      bins dlc_3 = {3};
      bins dlc_4 = {4};
      bins dlc_5 = {5};
      bins dlc_6 = {6};
      bins dlc_7 = {7};
      bins dlc_8 = {8};   // UP-01, UP-03 boundary
    }

    cp_eff: coverpoint up_can_eff {
      bins standard = {0};  // UP-01
      bins extended = {1};  // UP-02
    }

    cp_rtr: coverpoint up_can_rtr {
      bins data_frame   = {0};  // UP-01
      bins remote_frame = {1};  // optional
    }

    cross_dlc_eff: cross cp_dlc, cp_eff {
      ignore_bins ext_low_dlc = binsof(cp_eff.extended) && (
        binsof(cp_dlc.dlc_1) || binsof(cp_dlc.dlc_2) || binsof(cp_dlc.dlc_3)
      );
    }
  endgroup

  // =========================================================================
  // CG9: Upstream EtherType Coverage (UP-01, UP-04)
  // =========================================================================
  covergroup up_ethertype_cg;
    option.per_instance = 1;
    option.name = "up_ethertype_cg";

    cp_mode: coverpoint bridge_ctrl_val[2:1] {
      bins gateway = {2'b01};  // EtherType=0xCAFE
      bins tunnel  = {2'b10};  // EtherType=0xCABE
    }
  endgroup

  // =========================================================================
  // CG10: Downstream FSM State Coverage (DN-01..04, SYS-02)
  // =========================================================================
  covergroup dn_fsm_cg;
    option.per_instance = 1;
    option.name = "dn_fsm_cg";

    cp_state: coverpoint dn_fsm_state {
      bins idle        = {`DN_IDLE};
      bins read_bd     = {`DN_READ_BD};
      bins read_ram    = {`DN_READ_RAM};
      bins validate    = {`DN_VALIDATE};
      bins decap       = {`DN_DECAP};
      bins queue_chk   = {`DN_QUEUE_CHK};
      bins enqueue     = {`DN_ENQUEUE};
      bins write_can   = {`DN_WRITE_CAN};
      bins wait_can_tx = {`DN_WAIT_CAN_TX};
      bins free_bd     = {`DN_FREE_BD};
    }
  endgroup

  // =========================================================================
  // CG11: Downstream Validation Coverage (DN-01..03)
  // =========================================================================
  covergroup dn_validate_cg;
    option.per_instance = 1;
    option.name = "dn_validate_cg";

    cp_ethertype: coverpoint dn_ethertype {
      bins gateway_ok = {`ETHERTYPE_GATEWAY};  // DN-01
      bins tunnel_ok  = {`ETHERTYPE_TUNNEL};   // DN-02
      bins invalid    = default;                // DN-02 (bad ethertype)
    }

    cp_valid: coverpoint dn_frame_valid {
      bins valid   = {1};  // DN-01
      bins invalid = {0};  // DN-02, DN-03
    }

    cp_dlc: coverpoint dn_can_dlc {
      bins valid_dlc   = {[0:8]};   // DN-01
      bins invalid_dlc = {[9:15]};  // DN-03
    }
  endgroup

  // =========================================================================
  // CG12: CAN TX Queue Coverage (QUE-01, DN-04)
  // =========================================================================
  covergroup queue_cg;
    option.per_instance = 1;
    option.name = "queue_cg";

    cp_depth: coverpoint dn_queue_depth {
      bins empty   = {0};
      bins low     = {[1:3]};
      // Queue depth > 3 not reachable with sequential frame processing
      ignore_bins mid  = {[4:6]};
      ignore_bins high = {7};
      ignore_bins full = {8};
    }
  endgroup

  // =========================================================================
  // CG13: Arbiter Contention Coverage (ARB-01, SYS-03)
  // =========================================================================
  covergroup arbiter_cg;
    option.per_instance = 1;
    option.name = "arbiter_cg";

    cp_can_contention: coverpoint can_bus_contention {
      bins no_contention = {0};
      // CAN bus contention requires both FSMs to request CAN bus
      // on the exact same cycle; extremely unlikely with sequential FSM
      ignore_bins contention = {1};
    }

    cp_eth_contention: coverpoint eth_bus_contention {
      bins no_contention = {0};
      // ETH bus contention requires both FSMs to request ETH bus
      // on the exact same cycle; achievable in SYS-03/SYS-04
      ignore_bins contention = {1};
    }
  endgroup

  // =========================================================================
  // CG14: Status Counter Coverage (CNT-01)
  // =========================================================================
  covergroup counter_cg;
    option.per_instance = 1;
    option.name = "counter_cg";

    cp_can_rx: coverpoint cnt_can_rx_val {
      bins zero     = {0};
      bins nonzero  = {[1:32'hFFFFFFFF]};
    }
    cp_eth_tx: coverpoint cnt_eth_tx_val {
      bins zero     = {0};
      bins nonzero  = {[1:32'hFFFFFFFF]};
    }
    cp_eth_rx: coverpoint cnt_eth_rx_val {
      bins zero     = {0};
      bins nonzero  = {[1:32'hFFFFFFFF]};
    }
    cp_can_tx: coverpoint cnt_can_tx_val {
      bins zero     = {0};
      bins nonzero  = {[1:32'hFFFFFFFF]};
    }
    cp_filtered: coverpoint cnt_filtered_val {
      bins zero     = {0};
      bins nonzero  = {[1:32'hFFFFFFFF]};
    }
    cp_errors: coverpoint cnt_errors_val {
      bins zero     = {0};
      bins nonzero  = {[1:32'hFFFFFFFF]};
    }
  endgroup

  // =========================================================================
  // CG15: Full Duplex Coverage (SYS-03, SYS-04)
  // =========================================================================
  covergroup fullduplex_cg;
    option.per_instance = 1;
    option.name = "fullduplex_cg";

    cp_up_active: coverpoint (up_fsm_state != `UP_IDLE) {
      bins idle   = {0};
      bins active = {1};
    }

    cp_dn_active: coverpoint (dn_fsm_state != `DN_IDLE) {
      bins idle   = {0};
      bins active = {1};
    }

    cross_duplex: cross cp_up_active, cp_dn_active;
  endgroup

  // =========================================================================
  // CG16: Filter Table Entry Coverage (REG-04)
  // =========================================================================
  covergroup filter_table_cg;
    option.per_instance = 1;
    option.name = "filter_table_cg";

    cp_filter_idx: coverpoint ((cov_addr - `REG_FILTER_TBL_BASE) >> 2) {
      bins entry[16] = {[0:15]};
    }
  endgroup

  // =========================================================================
  // Constructor
  // =========================================================================
  function new(string name = "bridge_coverage", uvm_component parent = null);
    super.new(name, parent);
    reg_addr_cg      = new();
    reg_data_cg      = new();
    reg_reset_cg     = new();
    bridge_mode_cg   = new();
    filter_config_cg = new();
    filter_result_cg = new();
    up_fsm_cg        = new();
    up_can_frame_cg  = new();
    up_ethertype_cg  = new();
    dn_fsm_cg        = new();
    dn_validate_cg   = new();
    queue_cg         = new();
    arbiter_cg       = new();
    counter_cg       = new();
    fullduplex_cg    = new();
    filter_table_cg  = new();
  endfunction

  // =========================================================================
  // sample_fsm_states() — call from monitor at each clock edge
  // =========================================================================
  virtual function void sample_fsm_states(
    logic [3:0] up_state, logic [3:0] dn_state,
    bit up_filter_drop_val, logic [28:0] can_id, logic [3:0] can_dlc,
    bit can_eff, bit can_rtr,
    logic [15:0] ethertype, logic [3:0] dlc_dn, bit frame_valid,
    logic [3:0] q_depth,
    bit can_contention, bit eth_contention
  );
    up_fsm_state      = up_state;
    dn_fsm_state      = dn_state;
    up_filter_drop    = up_filter_drop_val;
    up_can_id         = can_id;
    up_can_dlc        = can_dlc;
    up_can_eff        = can_eff;
    up_can_rtr        = can_rtr;
    dn_ethertype      = ethertype;
    dn_can_dlc        = dlc_dn;
    dn_frame_valid    = frame_valid;
    dn_queue_depth    = q_depth;
    can_bus_contention = can_contention;
    eth_bus_contention = eth_contention;

    up_fsm_cg.sample();
    dn_fsm_cg.sample();
    fullduplex_cg.sample();
    queue_cg.sample();
    arbiter_cg.sample();

    // Sample frame coverage only during relevant states
    if (up_state == `UP_FILTER) begin
      filter_result_cg.sample();
      up_can_frame_cg.sample();
    end
    if (up_state == `UP_ENCAP)
      up_ethertype_cg.sample();
    if (dn_state == `DN_VALIDATE)
      dn_validate_cg.sample();
  endfunction

  // =========================================================================
  // write() — called by monitor for each WB transaction on host port
  // =========================================================================
  virtual function void write(wishbone_transaction t);
    cov_addr    = t.address;
    cov_data    = t.is_read ? t.read_data : t.write_data;
    cov_is_read = t.is_read;

    // CG1: Register address coverage (bridge register space 0x00-0x7C)
    if (cov_addr <= 8'h7C)
      reg_addr_cg.sample();

    // CG2: Data pattern coverage (writes only)
    if (!cov_is_read && cov_addr <= 8'h7C)
      reg_data_cg.sample();

    // CG3: Reset read coverage
    if (cov_is_read && cov_addr <= 8'h7C)
      reg_reset_cg.sample();

    // CG4: Bridge mode (BRIDGE_CTRL write)
    if (!cov_is_read && cov_addr == `REG_BRIDGE_CTRL) begin
      bridge_ctrl_val = cov_data;
      bridge_mode_cg.sample();
    end

    // CG5: Filter config (FILTER_CTRL write)
    if (!cov_is_read && cov_addr == `REG_FILTER_CTRL) begin
      filter_ctrl_val = cov_data;
      filter_config_cg.sample();
    end

    // CG16: Filter table entry (0x1C-0x58)
    if (!cov_is_read && cov_addr >= `REG_FILTER_TBL_BASE && cov_addr <= `REG_FILTER_TBL_END)
      filter_table_cg.sample();

    // CG14: Counter reads
    if (cov_is_read) begin
      case (cov_addr)
        `REG_CNT_CAN_RX:   begin cnt_can_rx_val   = cov_data; counter_cg.sample(); end
        `REG_CNT_ETH_TX:   begin cnt_eth_tx_val   = cov_data; counter_cg.sample(); end
        `REG_CNT_ETH_RX:   begin cnt_eth_rx_val   = cov_data; counter_cg.sample(); end
        `REG_CNT_CAN_TX:   begin cnt_can_tx_val   = cov_data; counter_cg.sample(); end
        `REG_CNT_FILTERED: begin cnt_filtered_val = cov_data; counter_cg.sample(); end
        `REG_CNT_ERRORS:   begin cnt_errors_val   = cov_data; counter_cg.sample(); end
      endcase
    end

    // MAC address writes
    if (!cov_is_read && cov_addr == `REG_DST_MAC_HI) dst_mac_hi_val = cov_data;
    if (!cov_is_read && cov_addr == `REG_SRC_MAC_HI) src_mac_hi_val = cov_data;

  endfunction : write

  // =========================================================================
  // check_phase — report final coverage
  // =========================================================================
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("BRIDGE_COV", $sformatf(
      "reg_addr=%.1f%%, reg_data=%.1f%%, reg_reset=%.1f%%",
      reg_addr_cg.get_coverage(),
      reg_data_cg.get_coverage(),
      reg_reset_cg.get_coverage()), UVM_LOW)

    `uvm_info("BRIDGE_COV", $sformatf(
      "bridge_mode=%.1f%%, filter_cfg=%.1f%%, filter_result=%.1f%%, filter_tbl=%.1f%%",
      bridge_mode_cg.get_coverage(),
      filter_config_cg.get_coverage(),
      filter_result_cg.get_coverage(),
      filter_table_cg.get_coverage()), UVM_LOW)

    `uvm_info("BRIDGE_COV", $sformatf(
      "up_fsm=%.1f%%, up_frame=%.1f%%, up_ethtype=%.1f%%",
      up_fsm_cg.get_coverage(),
      up_can_frame_cg.get_coverage(),
      up_ethertype_cg.get_coverage()), UVM_LOW)

    `uvm_info("BRIDGE_COV", $sformatf(
      "dn_fsm=%.1f%%, dn_validate=%.1f%%",
      dn_fsm_cg.get_coverage(),
      dn_validate_cg.get_coverage()), UVM_LOW)

    `uvm_info("BRIDGE_COV", $sformatf(
      "queue=%.1f%%, arbiter=%.1f%%, counters=%.1f%%, fullduplex=%.1f%%",
      queue_cg.get_coverage(),
      arbiter_cg.get_coverage(),
      counter_cg.get_coverage(),
      fullduplex_cg.get_coverage()), UVM_LOW)
  endfunction : check_phase

endclass : bridge_coverage
