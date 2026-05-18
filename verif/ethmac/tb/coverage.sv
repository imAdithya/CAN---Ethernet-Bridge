// coverage.sv — Functional coverage for the Ethernet MAC UVM testbench
// Samples wishbone transactions to track register access patterns,
// data patterns, and DUT behavior exercised by each test.

`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ethmac_defines.v"

class eth_coverage extends uvm_subscriber #(wishbone_transaction);
  `uvm_component_utils(eth_coverage)

  // =========================================================================
  // Internal state for coverage sampling
  // =========================================================================
  logic [31:0] cov_addr;     // Register byte address from transaction
  logic [31:0] cov_data;     // Data from transaction
  bit          cov_is_read;  // 1 = read, 0 = write

  // Track previous transaction for back-to-back detection
  logic [31:0] prev_addr;
  bit          prev_valid;
  bit          prev_is_read;

  // =========================================================================
  // === REGISTER COVERGROUPS (CG1–CG5)
  // =========================================================================

  // CG1: Register Address Coverage
  covergroup reg_addr_cg;
    option.per_instance = 1;
    option.name = "reg_addr_cg";

    cp_addr: coverpoint cov_addr {
      bins moder       = {32'h00};
      bins int_src     = {32'h04};
      bins int_mask    = {32'h08};
      bins ipgt        = {32'h0C};
      bins ipgr1       = {32'h10};
      bins ipgr2       = {32'h14};
      bins pkt_len     = {32'h18};
      bins coll_conf   = {32'h1C};
      bins tx_bd_num   = {32'h20};
      bins ctrl_moder  = {32'h24};
      bins miimoder    = {32'h28};
      bins miicommand  = {32'h2C};
      bins miiaddr     = {32'h30};
      bins miitx       = {32'h34};
      bins miirx       = {32'h38};
      bins miistat     = {32'h3C};
      bins mac_addr0   = {32'h40};
      bins mac_addr1   = {32'h44};
      bins hash0       = {32'h48};
      bins hash1       = {32'h4C};
      bins tx_ctrl     = {32'h50};
      bins rx_ctrl     = {32'h54};
    }

    cp_access: coverpoint cov_is_read {
      bins read  = {1};
      bins write = {0};
    }

    cross_addr_access: cross cp_addr, cp_access {
      ignore_bins ro_write =
        binsof(cp_access.write) &&
        ( binsof(cp_addr.int_src) ||
          binsof(cp_addr.miirx)  ||
          binsof(cp_addr.miistat)
        );
    }
  endgroup

  // CG2: Register Data Pattern Coverage
  covergroup reg_data_pattern_cg;
    option.per_instance = 1;
    option.name = "reg_data_pattern_cg";

    cp_data_pattern: coverpoint cov_data {
      bins all_zeros     = {32'h0000_0000};
      bins all_ones      = {32'hFFFF_FFFF};
      bins low_byte_only = {[32'h0000_0001 : 32'h0000_00FF]};
      bins low_word_only = {[32'h0000_0100 : 32'h0000_FFFF]};
      bins upper_bits    = {[32'h0001_0000 : 32'hFFFF_FFFE]};
    }

    cp_write_only: coverpoint cov_is_read {
      bins write = {0};
    }

    cross_data_write: cross cp_data_pattern, cp_write_only;
  endgroup

  // CG3: Read-Only Register Access Coverage
  covergroup reg_ro_access_cg;
    option.per_instance = 1;
    option.name = "reg_ro_access_cg";

    cp_ro_reg: coverpoint cov_addr {
      bins int_source  = {32'h04};
      bins miirx_data  = {32'h38};
      bins miistatus   = {32'h3C};
    }

    cp_ro_access: coverpoint cov_is_read {
      bins read         = {1};
      bins write_attempt = {0};
    }

    cross_ro_rw: cross cp_ro_reg, cp_ro_access;
  endgroup

  // CG4: Back-to-Back (Burst) Access Coverage
  bit          cov_is_burst_write;
  bit          cov_is_burst_read;
  bit          cov_is_wr_rd_pair;

  covergroup reg_burst_cg;
    option.per_instance = 1;
    option.name = "reg_burst_cg";

    cp_burst_write: coverpoint cov_is_burst_write {
      bins burst_write_seen = {1};
    }

    cp_burst_read: coverpoint cov_is_burst_read {
      bins burst_read_seen = {1};
    }

    cp_wr_rd_pair: coverpoint cov_is_wr_rd_pair {
      bins wr_rd_pair_seen = {1};
    }
  endgroup

  // CG5: Reset Value Read Coverage
  covergroup reg_reset_read_cg;
    option.per_instance = 1;
    option.name = "reg_reset_read_cg";

    cp_reset_reg: coverpoint cov_addr {
      bins moder       = {32'h00};
      bins int_src     = {32'h04};
      bins int_mask    = {32'h08};
      bins ipgt        = {32'h0C};
      bins ipgr1       = {32'h10};
      bins ipgr2       = {32'h14};
      bins pkt_len     = {32'h18};
      bins coll_conf   = {32'h1C};
      bins tx_bd_num   = {32'h20};
      bins ctrl_moder  = {32'h24};
      bins miimoder    = {32'h28};
      bins miiaddr     = {32'h30};
      bins miitx       = {32'h34};
      bins miirx       = {32'h38};
      bins miistat     = {32'h3C};
      bins mac_addr0   = {32'h40};
      bins mac_addr1   = {32'h44};
      bins hash0       = {32'h48};
      bins hash1       = {32'h4C};
      bins tx_ctrl     = {32'h50};
    }

    cp_is_read: coverpoint cov_is_read {
      bins read = {1};
    }

    cross_reset_read: cross cp_reset_reg, cp_is_read;
  endgroup

  // =========================================================================
  // === TX COVERGROUPS (CG6–CG9)
  // =========================================================================

  // --- TX internal state extracted from transactions ---
  logic [15:0] tx_pkt_length;      // Length from BD status write (upper 16 bits)
  logic [15:0] tx_bd_status_bits;  // Status flags from BD status write (lower 16 bits)
  logic [15:0] tx_completion_bits; // Status flags from BD status read (after TX done)
  logic [31:0] tx_moder_val;       // MODER register value written
  logic [31:0] tx_bd_num_val;      // TX_BD_NUM register value written
  bit          tx_bd_write_seen;   // Flag: a TX BD status write was observed
  bit          tx_bd_read_seen;    // Flag: a TX BD status read was observed
  bit          tx_moder_seen;      // Flag: MODER write observed
  bit          tx_bd_num_seen;     // Flag: TX_BD_NUM write observed

  // CG6: TX Packet Length Coverage
  // Sampled when a TX BD status word is written (contains length in [31:16])
  covergroup tx_pkt_length_cg;
    option.per_instance = 1;
    option.name = "tx_pkt_length_cg";

    cp_tx_length: coverpoint tx_pkt_length {
      bins len_runt      = {[1:63]};          // tx_min_packet_seq (payload=20)
      bins len_short     = {[64:127]};        // Small packets (tx_broad_multi: 100)
      bins len_mid       = {[128:1023]};      // Medium packets (tx_full_ring: 400, 1000)
      bins len_big       = {[1024:1514]};     // tx_max_packet_seq (1514)
      bins len_huge      = {[1515:65535]};    // tx_huge_packet_seq (2500)
    }
  endgroup

  // CG7: TX BD Control Bits Coverage
  // Sampled when a TX BD status word is written (observes which BD flags are set)
  covergroup tx_bd_ctrl_cg;
    option.per_instance = 1;
    option.name = "tx_bd_ctrl_cg";

    // Individual bit coverage
    cp_bd_rd:   coverpoint tx_bd_status_bits[15] { bins set = {1}; }
    cp_bd_irq:  coverpoint tx_bd_status_bits[14] { bins set = {1}; }
    cp_bd_wrap: coverpoint tx_bd_status_bits[13] {
      bins set   = {1};
      bins clear = {0};
    }
    cp_bd_pad:  coverpoint tx_bd_status_bits[12] {
      bins set   = {1};
      bins clear = {0};
    }
    cp_bd_crc:  coverpoint tx_bd_status_bits[11] {
      bins set   = {1};
      bins clear = {0};
    }

    // Cross PAD × CRC: tests different combinations
    cross_pad_crc: cross cp_bd_pad, cp_bd_crc;
  endgroup

  // CG8: TX MODER Feature Coverage
  // Sampled when MODER register is written — tracks which TX features are enabled
  covergroup tx_moder_cg;
    option.per_instance = 1;
    option.name = "tx_moder_cg";

    cp_txen:     coverpoint tx_moder_val[1]  { bins enabled = {1}; }
    cp_pad:      coverpoint tx_moder_val[15] { bins enabled = {1}; }
    cp_crcen:    coverpoint tx_moder_val[13] { bins enabled = {1}; }
    cp_hugen:    coverpoint tx_moder_val[14] {
      bins enabled  = {1};   // tx_huge_packet_seq
      bins disabled = {0};   // All other TX tests
    }
    cp_dlycrcen: coverpoint tx_moder_val[12] {
      bins enabled  = {1};   // tx_dly_crc_seq
      bins disabled = {0};   // All other TX tests
    }
    cp_fulld:    coverpoint tx_moder_val[10] {
      bins half_duplex = {0};   // All TX tests use half duplex
    }
  endgroup

  // CG9: TX Completion Status Coverage
  // Sampled when TX BD status is READ (after TX completion) — observes result bits
  covergroup tx_completion_cg;
    option.per_instance = 1;
    option.name = "tx_completion_cg";

    // Bit 15 (RD) should be 0 for completed transmissions
    cp_rd_cleared: coverpoint tx_completion_bits[15] {
      bins cleared = {0};  // TX completed
    }

    // Bit 8: Underrun
    cp_ur: coverpoint tx_completion_bits[8] {
      bins no_underrun = {0};
    }

    // Bit 3: Retry Limit
    cp_rl: coverpoint tx_completion_bits[3] {
      bins no_retry_limit = {0};
    }

    // Bit 2: Late Collision
    cp_lc: coverpoint tx_completion_bits[2] {
      bins no_late_collision = {0};
    }

    // Bit 1: Defer Indication
    cp_def: coverpoint tx_completion_bits[1] {
      bins no_defer  = {0};
    }

    // Bit 0: Carrier Sense Lost
    cp_cs: coverpoint tx_completion_bits[0] {
      bins no_cs_lost = {0};
    }

    // Retry Count [7:4]
    cp_retry_cnt: coverpoint tx_completion_bits[7:4] {
      bins zero_retries = {0};
    }
  endgroup

  // =========================================================================
  // === RX COVERGROUPS (CG10–CG14)
  // =========================================================================

  // --- RX internal state ---
  logic [15:0] rx_pkt_length;         // Length from RX BD status read
  logic [15:0] rx_bd_status_bits;     // RX BD status flags
  logic [31:0] rx_moder_val;          // MODER value when RXEN is set
  bit          rx_bd_read_seen;       // Flag: RX BD status read observed
  bit          rx_moder_seen;         // Flag: MODER write with RXEN observed
  int          rx_bd_arm_count;       // Count of RX BDs armed in current test

  // CG10: RX Packet Length Coverage
  // Sampled when RX BD status is read and EMPTY bit cleared (packet received)
  covergroup rx_pkt_length_cg;
    option.per_instance = 1;
    option.name = "rx_pkt_length_cg";

    cp_rx_length: coverpoint rx_pkt_length {
      bins len_short  = {[48:127]};       // rx_host_seq (68B), most RX tests
      bins len_mid    = {[128:1023]};     // rand_rx_seq variable packets
      bins len_large  = {[1024:1518]};    // base_rx_seq (1518B)
    }
  endgroup

  // CG11: RX BD Completion Status Coverage
  // Sampled when RX BD is read with EMPTY=0 (packet received)
  covergroup rx_bd_completion_cg;
    option.per_instance = 1;
    option.name = "rx_bd_completion_cg";

    // Bit 15 (EMPTY) cleared = packet received
    cp_empty_cleared: coverpoint rx_bd_status_bits[15] {
      bins received = {0};
    }

    // Error flags
    cp_latecol:  coverpoint rx_bd_status_bits[0] { bins no_err = {0}; }
    cp_crc_err:  coverpoint rx_bd_status_bits[1] { bins no_err = {0}; }
    cp_short:    coverpoint rx_bd_status_bits[2] { bins no_err = {0}; }
    cp_too_long: coverpoint rx_bd_status_bits[3] { bins no_err = {0}; }
    cp_dribble:  coverpoint rx_bd_status_bits[4] { bins no_err = {0}; }
    cp_overrun:  coverpoint rx_bd_status_bits[6] { bins no_err = {0}; }

    // Bit 7: AddressMiss — key for promiscuous_mode_seq
    cp_miss: coverpoint rx_bd_status_bits[7] {
      bins match = {0};   // Normal: address matched
      bins miss  = {1};   // promiscuous_mode_seq: PRO=1, address didn't match
    }
  endgroup

  // CG12: RX MODER Feature Coverage
  // Sampled when MODER is written with RXEN=1 — tracks RX features enabled
  covergroup rx_moder_cg;
    option.per_instance = 1;
    option.name = "rx_moder_cg";

    cp_rxen: coverpoint rx_moder_val[0] {
      bins enabled = {1};
    }
    cp_pro: coverpoint rx_moder_val[5] {
      bins disabled = {0};  // Normal filtering (rx_host_seq, addr_match_rx)
      bins enabled  = {1};  // promiscuous_mode_seq
    }
    cp_bro: coverpoint rx_moder_val[3] {
      bins accept_broadcast = {0};  // Most RX tests
      bins reject_broadcast = {1};  // addr_match_rx_seq Phase 2
    }
    cp_iam: coverpoint rx_moder_val[4] {
      bins disabled = {0};  // Most tests
      bins enabled  = {1};  // addr_match_rx_seq
    }
    cp_hugen: coverpoint rx_moder_val[14] {
      bins disabled = {0};  // Most tests
      bins enabled  = {1};  // huge_rx_seq Phase 2
    }
    cp_dlycrcen: coverpoint rx_moder_val[12] {
      bins disabled = {0};  // Most tests
      bins enabled  = {1};  // delayed_crc_rx_seq Phase 2
    }
    cp_crcen: coverpoint rx_moder_val[13] {
      bins disabled = {0};  // delayed_crc_rx_seq (DlyCrcEn w/o CRCEN)
      bins enabled  = {1};  // Most RX tests
    }

    // Cross: PRO × BRO — tests key filtering combinations
    cross_pro_bro: cross cp_pro, cp_bro {
      // PRO=1 with BRO=1 is not tested (promiscuous doesn't need BRO)
      ignore_bins untested = binsof(cp_pro.enabled) && binsof(cp_bro.reject_broadcast);
    }
  endgroup

  // CG13: RX BD Count Coverage
  // Tracks how many RX BDs are armed (1 vs multi-BD tests)
  covergroup rx_bd_count_cg;
    option.per_instance = 1;
    option.name = "rx_bd_count_cg";

    cp_rx_bd_count: coverpoint rx_bd_arm_count {
      bins single_bd = {1};       // rx_host_seq, base_rx_seq
      bins multi_bd  = {[2:8]};   // b2b_rx_seq(5), rand_rx_seq(8), huge_rx(4)
    }
  endgroup

  // CG14: RX Address Filtering Coverage
  // Sampled from HASH and MAC_ADDR writes to track filtering configs
  logic [31:0] rx_hash0_val;
  logic [31:0] rx_hash1_val;
  bit          rx_hash_written;

  covergroup rx_addr_filter_cg;
    option.per_instance = 1;
    option.name = "rx_addr_filter_cg";

    cp_hash0: coverpoint rx_hash0_val {
      bins all_zeros  = {32'h00000000};    // rand_rx_seq, promiscuous_mode_seq
      bins all_ones   = {32'hFFFFFFFF};    // addr_match_rx Phase 3
      bins partial    = default;            // addr_match_rx Phase 4
    }
    cp_hash1: coverpoint rx_hash1_val {
      bins all_zeros  = {32'h00000000};
      bins all_ones   = {32'hFFFFFFFF};
      bins partial    = default;
    }
  endgroup

  // =========================================================================
  // === HD COVERGROUPS (CG15–CG17)
  // =========================================================================

  // --- HD internal state ---
  logic [31:0] hd_moder_val;          // MODER value when TXEN=1, FULLD=0
  logic [31:0] hd_collconf_val;       // COLLCONF register value
  logic [15:0] hd_completion_bits;    // TX BD completion bits for HD tests
  bit          hd_moder_seen;
  bit          hd_collconf_seen;

  // CG15: HD MODER Feature Coverage
  // Sampled when MODER is written with TXEN=1 and FULLD=0 (half-duplex TX)
  covergroup hd_moder_cg;
    option.per_instance = 1;
    option.name = "hd_moder_cg";

    cp_txen: coverpoint hd_moder_val[1] {
      bins enabled = {1};
    }
    cp_fulld: coverpoint hd_moder_val[10] {
      bins half_duplex = {0};  // All HD tests
    }
    cp_pad: coverpoint hd_moder_val[15] {
      bins enabled = {1};  // All HD tests use PAD
    }
    cp_crcen: coverpoint hd_moder_val[13] {
      bins enabled = {1};  // All HD tests use CRC
    }
  endgroup

  // CG16: COLLCONF Register Coverage
  // Sampled when COLLCONF is written
  covergroup hd_collconf_cg;
    option.per_instance = 1;
    option.name = "hd_collconf_cg";

    // MaxRet [19:16] — max retry count before abort
    cp_maxret: coverpoint hd_collconf_val[19:16] {
      bins max15 = {4'hF};  // All HD tests use MaxRet=15
    }

    // CollValid [5:0] — collision window size
    cp_collvalid: coverpoint hd_collconf_val[5:0] {
      bins window_63 = {6'h3F};  // All HD tests use CollValid=63
    }
  endgroup

  // CG17: HD TX Completion Status Coverage
  // Sampled when TX BD read shows RD=0 in an HD context (FULLD was 0)
  covergroup hd_tx_completion_cg;
    option.per_instance = 1;
    option.name = "hd_tx_completion_cg";

    // Bit 3: Retry Limit
    cp_rl: coverpoint hd_completion_bits[3] {
      bins no_rl  = {0};  // HD-01, HD-03, HD-04, HD-05
      bins rl_hit = {1};  // HD-02 (hd_max_collision_seq)
    }

    // Bit 2: Late Collision
    cp_lc: coverpoint hd_completion_bits[2] {
      bins no_lc       = {0};  // HD-01, HD-02, HD-04, HD-05
      bins late_coll   = {1};  // HD-03 (late_collision_seq)
    }

    // Bit 0: Carrier Sense Lost
    cp_cs: coverpoint hd_completion_bits[0] {
      bins no_cs   = {0};  // HD-01, HD-02, HD-03, HD-04
      bins cs_lost = {1};  // HD-05 (carrier_lost_seq)
    }

    // Retry Count [7:4]
    cp_retry_cnt: coverpoint hd_completion_bits[7:4] {
      bins zero_retries  = {0};           // HD-03, HD-05
      bins some_retries  = {[1:14]};      // HD-01 (1), HD-04 (3)
      bins max_retries   = {15};          // HD-02 (MaxRet=15 exceeded)
    }
  endgroup

  // =========================================================================
  // === FD COVERGROUPS (CG18–CG20)
  // =========================================================================

  // --- FD internal state ---
  logic [31:0] fd_moder_val;          // MODER value when TXEN=1, FULLD=1
  logic [31:0] fd_ctrlmoder_val;      // CTRLMODER register value
  logic [31:0] fd_tx_ctrl_val;        // TX_CTRL register value
  bit          fd_moder_seen;

  // CG18: FD MODER Feature Coverage
  // Sampled when MODER is written with TXEN=1 and FULLD=1 (full-duplex TX)
  covergroup fd_moder_cg;
    option.per_instance = 1;
    option.name = "fd_moder_cg";

    cp_fulld: coverpoint fd_moder_val[10] {
      bins full_duplex = {1};  // All FD tests
    }
    cp_txen: coverpoint fd_moder_val[1] {
      bins enabled = {1};  // All FD tests
    }
    cp_rxen: coverpoint fd_moder_val[0] {
      bins disabled = {0};  // FD-01 (tx_pause: TX only)
      bins enabled  = {1};  // FD-02, FD-03 (TXRX mode)
    }
    cp_pad: coverpoint fd_moder_val[15] {
      bins enabled = {1};  // All FD tests use PAD
    }
    cp_crcen: coverpoint fd_moder_val[13] {
      bins enabled = {1};  // All FD tests use CRC
    }
  endgroup

  // CG19: CTRLMODER Register Coverage
  // Sampled when CTRLMODER (0x24) is written
  covergroup fd_ctrlmoder_cg;
    option.per_instance = 1;
    option.name = "fd_ctrlmoder_cg";

    // Bit 2: TxFlow (TX pause frame generation)
    cp_txflow: coverpoint fd_ctrlmoder_val[2] {
      bins enabled  = {1};  // FD-01 (tx_pause_seq)
      bins disabled = {0};  // FD-02, FD-03 (RxFlow only)
    }

    // Bit 1: RxFlow (RX pause frame recognition)
    cp_rxflow: coverpoint fd_ctrlmoder_val[1] {
      bins enabled  = {1};  // FD-02, FD-03
      bins disabled = {0};  // FD-01 (TxFlow only)
    }
  endgroup

  // CG20: TX_CTRL Register Coverage
  // Sampled when TX_CTRL (0x50) is written
  covergroup fd_tx_ctrl_cg;
    option.per_instance = 1;
    option.name = "fd_tx_ctrl_cg";

    // Bit 16: TxPauseRq
    cp_pause_rq: coverpoint fd_tx_ctrl_val[16] {
      bins request = {1};  // FD-01 (tx_pause_seq triggers PAUSE)
    }

    // PauseTV [15:0]
    cp_pause_tv: coverpoint fd_tx_ctrl_val[15:0] {
      bins non_zero = {[1:65535]};  // FD-01 (PauseTV=0xABCD)
    }
  endgroup

  // =========================================================================
  // === ERR COVERGROUPS (CG21–CG23)
  // =========================================================================

  // --- ERR internal state ---
  logic [15:0] err_tx_status;         // TX BD status on completion
  logic [15:0] err_rx_status;         // RX BD status on completion
  logic [31:0] err_int_val;           // INT_SOURCE value on read

  // CG21: TX BD Error Status Coverage
  // Sampled when TX BD is read with RD=0 (TX completed)
  covergroup err_tx_status_cg;
    option.per_instance = 1;
    option.name = "err_tx_status_cg";

    // Bit 8: Underrun
    cp_underrun: coverpoint err_tx_status[8] {
      bins no_underrun = {0};  // Normal TX tests
      bins underrun    = {1};  // ERR-01 (tx_underrun_seq)
    }
  endgroup

  // CG22: RX BD Error Status Coverage
  // Sampled when RX BD is read with EMPTY=0 (frame received)
  covergroup err_rx_status_cg;
    option.per_instance = 1;
    option.name = "err_rx_status_cg";

    // Bit 1: CRC Error
    cp_crcerr: coverpoint err_rx_status[1] {
      bins no_crcerr = {0};  // ERR-04, ERR-06, ERR-07
      bins crcerr    = {1};  // ERR-03 (rx_bad_crc_seq)
    }

    // Bit 2: Short Frame
    cp_short: coverpoint err_rx_status[2] {
      bins no_short = {0};  // ERR-03, ERR-04, ERR-07
      bins short_fr = {1};  // ERR-06 phase 2 (rx_short_seq)
    }

    // Bit 4: Dribble Nibble
    cp_dribble: coverpoint err_rx_status[4] {
      bins no_dribble = {0};  // ERR-03, ERR-04, ERR-06
      bins dribble    = {1};  // ERR-07 (rx_dribble_seq)
    }

    // Bit 5: Invalid Symbol
    cp_invsimb: coverpoint err_rx_status[5] {
      bins no_invsimb = {0};  // ERR-03, ERR-06, ERR-07
      bins invsimb    = {1};  // ERR-04 (rx_invalid_symbol_seq)
    }
  endgroup

  // CG23: Error Interrupt Coverage
  // Sampled when INT_SOURCE is read
  covergroup err_int_source_cg;
    option.per_instance = 1;
    option.name = "err_int_source_cg";

    // Bit 1: TXE (TX Error)
    cp_txe: coverpoint err_int_val[1] {
      bins no_txe = {0};  // RX error tests
      bins txe    = {1};  // ERR-01 (tx_underrun)
    }

    // Bit 3: RXE (RX Error)
    cp_rxe: coverpoint err_int_val[3] {
      bins no_rxe = {0};  // ERR-01, ERR-06
      bins rxe    = {1};  // ERR-03, ERR-04, ERR-07
    }

    // Bit 4: BUSY (RX BD not available)
    cp_busy: coverpoint err_int_val[4] {
      bins no_busy = {0};  // All except ERR-02
      bins busy    = {1};  // ERR-02 (rx_overrun_seq)
    }
  endgroup

  // =========================================================================
  // === SYS COVERGROUPS (CG24–CG26)
  // =========================================================================

  // --- SYS internal state ---
  logic [31:0] sys_moder_val;          // MODER value on write
  logic [31:0] sys_int_mask_val;       // INT_MASK value on write
  logic [31:0] sys_bd_num_val;         // TX_BD_NUM value on write

  // CG24: SYS MODER Features Coverage
  // Sampled on MODER write — covers SYS-specific bits
  covergroup sys_moder_cg;
    option.per_instance = 1;
    option.name = "sys_moder_cg";

    // Bit 7: LoopBck
    cp_loopback: coverpoint sys_moder_val[7] {
      bins no_loopback = {0};  // SYS-02..06
      bins loopback    = {1};  // SYS-01 (loopback_seq)
    }

    // Bit 5: PRO (Promiscuous)
    cp_pro: coverpoint sys_moder_val[5] {
      bins no_pro = {0};  // MODER=0 resets, MODER=0xA003
      bins pro    = {1};  // SYS-01..06 (most use PRO=1)
    }

    // Bit 16: RecSmall
    cp_recsmall: coverpoint sys_moder_val[16] {
      bins no_recsmall = {0};  // Most tests
      bins recsmall    = {1};  // SYS-04 short frame rounds
    }
  endgroup

  // CG25: INT_MASK Coverage
  // Sampled on INT_MASK write (addr 0x08)
  covergroup sys_int_mask_cg;
    option.per_instance = 1;
    option.name = "sys_int_mask_cg";

    cp_mask_zero: coverpoint (sys_int_mask_val == 0) {
      bins mask_zero    = {1};  // SYS-02 reset_phase (mask=0)
      bins mask_nonzero = {0};  // SYS-02..06 mac_setup (mask=0x7F)
    }
  endgroup

  // CG26: TX_BD_NUM Configuration Coverage
  // Sampled on TX_BD_NUM write (addr 0x20)
  covergroup sys_bd_config_cg;
    option.per_instance = 1;
    option.name = "sys_bd_config_cg";

    cp_bd_num: coverpoint sys_bd_num_val {
      bins single  = {1};       // SYS-01..04 (TX_BD_NUM=1)
      bins few_bds = {[2:7]};   // SYS-06 (TX_BD_NUM=2)
      bins multi   = {[8:128]}; // SYS-05 (TX_BD_NUM=8)
    }
  endgroup

  // =========================================================================
  // === MIIM COVERGROUPS (CG27–CG29)
  // =========================================================================

  // --- MIIM internal state ---
  logic [31:0] miim_cmd_val;           // MIICOMMAND value on write
  logic [31:0] miim_moder_val;         // MIIMODER value on write
  logic [31:0] miim_status_val;        // MIISTATUS value on read

  // CG27: MIIM Command Coverage
  // Sampled on MIICOMMAND write (addr 0x2C)
  covergroup miim_command_cg;
    option.per_instance = 1;
    option.name = "miim_command_cg";

    cp_cmd: coverpoint miim_cmd_val[2:0] {
      bins cmd_clear    = {0};  // All tests (clear after op)
      bins cmd_scanstat = {1};  // MIIM-03 (scan)
      bins cmd_rstat    = {2};  // MIIM-01..06 (read)
      bins cmd_wctrl    = {4};  // MIIM-01..06 (write)
    }
  endgroup

  // CG28: MIIMODER Configuration Coverage
  // Sampled on MIIMODER write (addr 0x28)
  covergroup miim_moder_cg;
    option.per_instance = 1;
    option.name = "miim_moder_cg";

    // Bit 8: NoPre (suppress preamble)
    cp_nopre: coverpoint miim_moder_val[8] {
      bins nopre_off = {0};  // MIIM-01,02,03,05,06
      bins nopre_on  = {1};  // MIIM-04
    }

    // Bits [7:0]: ClkDiv
    cp_clkdiv: coverpoint miim_moder_val[7:0] {
      bins div_min    = {[1:4]};    // MIIM-05 div=2
      bins div_med    = {[5:49]};   // MIIM-01..04,06 div=10, MIIM-05 div=5
      bins div_large  = {[50:254]}; // MIIM-05 div=50
      bins div_max    = {255};      // MIIM-05 div=255
    }
  endgroup

  // CG29: MIISTATUS Read Coverage
  // Sampled on MIISTATUS read (addr 0x3C)
  covergroup miim_status_cg;
    option.per_instance = 1;
    option.name = "miim_status_cg";

    // Bit 1: Busy
    cp_busy: coverpoint miim_status_val[1] {
      bins not_busy = {0};  // After completion
      bins busy     = {1};  // During operation (MIIM-02,03)
    }

    // Bit 2: Nvalid
    cp_nvalid: coverpoint miim_status_val[2] {
      bins valid   = {0};  // Most reads
      bins nvalid  = {1};  // MIIM-03 (scan start)
    }
  endgroup

  // =========================================================================
  // === BASE CONFIG COVERGROUP (CG30)
  // =========================================================================

  logic [31:0] base_config_addr;  // Config register address on write

  // CG30: Configuration Register Write Completeness
  // Sampled on writes to any of the 9 essential MAC config registers
  covergroup base_config_cg;
    option.per_instance = 1;
    option.name = "base_config_cg";

    cp_config_reg: coverpoint base_config_addr {
      bins moder      = {32'h00};  // MODER
      bins ipgt       = {32'h0C};  // IPGT
      bins ipgr1      = {32'h10};  // IPGR1
      bins ipgr2      = {32'h14};  // IPGR2
      bins packetlen  = {32'h18};  // PACKETLEN
      bins collconf   = {32'h1C};  // COLLCONF
      bins tx_bd_num  = {32'h20};  // TX_BD_NUM
      bins mac_addr0  = {32'h40};  // MAC_ADDR0
      bins mac_addr1  = {32'h44};  // MAC_ADDR1
    }
  endgroup

  // =========================================================================
  // Constructor
  // =========================================================================
  function new(string name = "eth_coverage", uvm_component parent = null);
    super.new(name, parent);
    // Register covergroups
    reg_addr_cg         = new();
    reg_data_pattern_cg = new();
    reg_ro_access_cg    = new();
    reg_burst_cg        = new();
    reg_reset_read_cg   = new();
    // TX covergroups
    tx_pkt_length_cg    = new();
    tx_bd_ctrl_cg       = new();
    tx_moder_cg         = new();
    tx_completion_cg    = new();
    // RX covergroups
    rx_pkt_length_cg    = new();
    rx_bd_completion_cg = new();
    rx_moder_cg         = new();
    rx_bd_count_cg      = new();
    rx_addr_filter_cg   = new();
    // HD covergroups
    hd_moder_cg         = new();
    hd_collconf_cg      = new();
    hd_tx_completion_cg = new();
    // FD covergroups
    fd_moder_cg         = new();
    fd_ctrlmoder_cg     = new();
    fd_tx_ctrl_cg       = new();
    // ERR covergroups
    err_tx_status_cg    = new();
    err_rx_status_cg    = new();
    err_int_source_cg   = new();
    // SYS covergroups
    sys_moder_cg        = new();
    sys_int_mask_cg     = new();
    sys_bd_config_cg    = new();
    // MIIM covergroups
    miim_command_cg     = new();
    miim_moder_cg       = new();
    miim_status_cg      = new();
    // BASE covergroup
    base_config_cg      = new();
    prev_valid = 0;
    rx_bd_arm_count = 0;
    hd_moder_seen = 0;
    fd_moder_seen = 0;
  endfunction

  // =========================================================================
  // write() — called by the monitor for each wishbone transaction
  // =========================================================================
  virtual function void write(wishbone_transaction t);
    // Skip DMA bulk data transfers (memory reads/writes for packet data)
    if (t.is_dma_txn)
      return;

    cov_addr    = t.address;
    cov_data    = t.is_read ? t.read_data : t.write_data;
    cov_is_read = t.is_read;

    // Reset per-transaction flags
    tx_bd_write_seen = 0;
    tx_bd_read_seen  = 0;
    tx_moder_seen    = 0;
    tx_bd_num_seen   = 0;

    // =================================================================
    // REGISTER COVERAGE (CG1–CG5)
    // =================================================================

    // --- CG1: Register address coverage ---
    if (cov_addr <= 32'h58)
      reg_addr_cg.sample();

    // --- CG2: Data pattern coverage (writes only) ---
    if (!cov_is_read && cov_addr <= 32'h58)
      reg_data_pattern_cg.sample();

    // --- CG3: RO register access ---
    if (cov_addr == 32'h04 || cov_addr == 32'h38 || cov_addr == 32'h3C)
      reg_ro_access_cg.sample();

    // --- CG4: Burst / back-to-back detection ---
    cov_is_burst_write = 0;
    cov_is_burst_read  = 0;
    cov_is_wr_rd_pair  = 0;

    if (prev_valid && cov_addr <= 32'h58) begin
      if (!prev_is_read && !cov_is_read)
        cov_is_burst_write = 1;
      if (prev_is_read && cov_is_read)
        cov_is_burst_read = 1;
      if (!prev_is_read && cov_is_read && prev_addr == cov_addr)
        cov_is_wr_rd_pair = 1;
    end

    if (cov_is_burst_write || cov_is_burst_read || cov_is_wr_rd_pair)
      reg_burst_cg.sample();

    // --- CG5: Reset read coverage ---
    if (cov_is_read && cov_addr <= 32'h58)
      reg_reset_read_cg.sample();

    // =================================================================
    // TX COVERAGE (CG6–CG9)
    // =================================================================

    // Detect TX BD status WRITE (addresses 0x400, 0x408, 0x410, ... in steps of 8)
    // BD status registers are at even 8-byte boundaries in the BD region
    if (!cov_is_read && cov_addr >= 32'h400 && cov_addr < 32'h800) begin
      // Check if this is a status word (offset 0 within 8-byte BD) not a pointer (offset 4)
      if ((cov_addr & 32'h7) == 0) begin
        tx_pkt_length     = cov_data[31:16];
        tx_bd_status_bits = cov_data[15:0];
        tx_bd_write_seen  = 1;

        // CG6: Packet length
        tx_pkt_length_cg.sample();

        // CG7: BD control bits (only sample when RD bit is set = arming a descriptor)
        if (tx_bd_status_bits[15])
          tx_bd_ctrl_cg.sample();
      end
    end

    // Detect TX BD status READ (polling for completion)
    if (cov_is_read && cov_addr >= 32'h400 && cov_addr < 32'h800) begin
      if ((cov_addr & 32'h7) == 0) begin
        tx_completion_bits = cov_data[15:0];
        tx_bd_read_seen    = 1;

        // CG9: Completion status (only when RD bit is cleared = TX done)
        if (!tx_completion_bits[15])
          tx_completion_cg.sample();

        // CG17: HD completion status (TX BD read with RD=0 and HD mode active)
        if (!tx_completion_bits[15] && hd_moder_seen) begin
          hd_completion_bits = cov_data[15:0];
          hd_tx_completion_cg.sample();
        end

        // CG21: ERR TX status (TX BD read with RD=0)
        if (!tx_completion_bits[15]) begin
          err_tx_status = cov_data[15:0];
          err_tx_status_cg.sample();
        end
      end
    end

    // Detect MODER write (addr 0x00)
    if (!cov_is_read && cov_addr == 32'h00) begin
      tx_moder_val  = cov_data;
      tx_moder_seen = 1;

      // CG8: MODER feature coverage (only when TXEN is set)
      if (cov_data[1])
        tx_moder_cg.sample();

      // CG12: RX MODER feature coverage (only when RXEN is set)
      if (cov_data[0]) begin
        rx_moder_val  = cov_data;
        rx_moder_seen = 1;
        rx_moder_cg.sample();
      end

      // CG15: HD MODER coverage (TXEN=1, FULLD=0 = half-duplex TX)
      if (cov_data[1] && !cov_data[10]) begin
        hd_moder_val  = cov_data;
        hd_moder_seen = 1;
        hd_moder_cg.sample();
      end

      // CG18: FD MODER coverage (TXEN=1, FULLD=1 = full-duplex TX)
      if (cov_data[1] && cov_data[10]) begin
        fd_moder_val  = cov_data;
        fd_moder_seen = 1;
        fd_moder_cg.sample();
      end

      // CG24: SYS MODER coverage (always sample on MODER write)
      sys_moder_val = cov_data;
      sys_moder_cg.sample();
    end

    // Detect INT_MASK write (addr 0x08) — CG25
    if (!cov_is_read && cov_addr == 32'h08) begin
      sys_int_mask_val = cov_data;
      sys_int_mask_cg.sample();
    end

    // Detect TX_BD_NUM write (addr 0x20) — CG26
    if (!cov_is_read && cov_addr == 32'h20) begin
      sys_bd_num_val = cov_data;
      sys_bd_config_cg.sample();
    end

    // Detect COLLCONF write (addr 0x1C) — CG16
    if (!cov_is_read && cov_addr == 32'h1C) begin
      hd_collconf_val  = cov_data;
      hd_collconf_seen = 1;
      hd_collconf_cg.sample();
    end

    // Detect CTRLMODER write (addr 0x24) — CG19
    if (!cov_is_read && cov_addr == 32'h24) begin
      fd_ctrlmoder_val = cov_data;
      fd_ctrlmoder_cg.sample();
    end

    // Detect TX_CTRL write (addr 0x50) — CG20
    if (!cov_is_read && cov_addr == 32'h50) begin
      fd_tx_ctrl_val = cov_data;
      fd_tx_ctrl_cg.sample();
    end

    // =================================================================
    // RX COVERAGE (CG10–CG14)
    // =================================================================

    // Detect RX BD arm (WRITE to RX BD region with EMPTY bit set)
    // RX BDs start after TX BDs. Default TX_BD_NUM=0x40, so RX base=0x600
    // But also support variable TX_BD_NUM: any BD write >=0x400 with EMPTY=1
    if (!cov_is_read && cov_addr >= 32'h400 && cov_addr < 32'h800) begin
      if ((cov_addr & 32'h7) == 0) begin  // BD status word
        // Count RX BD arms (EMPTY bit set = arming a receive descriptor)
        if (cov_data[15] && cov_addr >= 32'h600) begin
          rx_bd_arm_count++;
        end
      end
    end

    // Detect RX BD status READ (polling for received packets)
    // RX BDs are at addresses >= 0x600 (with default TX_BD_NUM=0x40)
    if (cov_is_read && cov_addr >= 32'h600 && cov_addr < 32'h800) begin
      if ((cov_addr & 32'h7) == 0) begin  // BD status word
        rx_bd_status_bits = cov_data[15:0];
        rx_pkt_length     = cov_data[31:16];
        rx_bd_read_seen   = 1;

        // CG10: RX packet length (only when EMPTY cleared = packet received)
        if (!rx_bd_status_bits[15] && rx_pkt_length > 0)
          rx_pkt_length_cg.sample();

        // CG11: RX BD completion status (only when EMPTY cleared)
        if (!rx_bd_status_bits[15])
          rx_bd_completion_cg.sample();
      end
    end

    // CG22: ERR RX BD status (any BD read with EMPTY=0 in RX region)
    // ERR tests use TX_BD_NUM=1, so RX BD starts at 0x408
    // Detect RX BD reads at any address >= 0x400 where addr is NOT a TX BD
    // by checking if MODER had RXEN=1 (not TXEN) or addr >= first RX BD
    if (cov_is_read && cov_addr >= 32'h400 && cov_addr < 32'h800) begin
      if ((cov_addr & 32'h7) == 0 && !cov_data[15]) begin  // BD status word, EMPTY=0
        // Heuristic: if this BD has RX error bits set OR was in the RX region
        // Sample for ERR coverage
        if (cov_data[5:0] != 0 || cov_addr >= 32'h408) begin
          err_rx_status = cov_data[15:0];
          err_rx_status_cg.sample();
        end
      end
    end

    // Detect HASH register writes (for CG14)
    if (!cov_is_read && cov_addr == 32'h48) begin
      rx_hash0_val = cov_data;
      rx_hash_written = 1;
    end
    if (!cov_is_read && cov_addr == 32'h4C) begin
      rx_hash1_val = cov_data;
      rx_hash_written = 1;
      // Sample after HASH1 write (both HASH regs now set)
      rx_addr_filter_cg.sample();
    end

    // Sample RX BD count when MODER is written with RXEN
    // (this captures the number of BDs armed before enabling RX)
    if (!cov_is_read && cov_addr == 32'h00 && cov_data[0]) begin
      if (rx_bd_arm_count > 0) begin
        rx_bd_count_cg.sample();
        rx_bd_arm_count = 0;  // Reset for next test phase
      end
    end

    // CG23: ERR INT_SOURCE read coverage
    if (cov_is_read && cov_addr == 32'h04) begin
      err_int_val = cov_data;
      err_int_source_cg.sample();
    end

    // CG27: MIIM Command coverage (MIICOMMAND write, addr 0x2C)
    if (!cov_is_read && cov_addr == 32'h2C) begin
      miim_cmd_val = cov_data;
      miim_command_cg.sample();
    end

    // CG28: MIIMODER coverage (MIIMODER write, addr 0x28)
    if (!cov_is_read && cov_addr == 32'h28) begin
      miim_moder_val = cov_data;
      miim_moder_cg.sample();
    end

    // CG29: MIISTATUS coverage (MIISTATUS read, addr 0x3C)
    if (cov_is_read && cov_addr == 32'h3C) begin
      miim_status_val = cov_data;
      miim_status_cg.sample();
    end

    // CG30: Base config register write coverage
    // Sample on write to any of the 9 essential config registers
    if (!cov_is_read && (
        cov_addr == 32'h00 || cov_addr == 32'h0C || cov_addr == 32'h10 ||
        cov_addr == 32'h14 || cov_addr == 32'h18 || cov_addr == 32'h1C ||
        cov_addr == 32'h20 || cov_addr == 32'h40 || cov_addr == 32'h44
    )) begin
      base_config_addr = cov_addr;
      base_config_cg.sample();
    end

    // Track for next iteration (register space only)
    prev_addr    = cov_addr;
    prev_is_read = cov_is_read;
    prev_valid   = (cov_addr <= 32'h58);

  endfunction : write

  // =========================================================================
  // check_phase — report final coverage
  // =========================================================================
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("COVERAGE", $sformatf(
      "reg_addr=%.1f%%, reg_data=%.1f%%, reg_ro=%.1f%%, reg_burst=%.1f%%, reg_reset=%.1f%%",
      reg_addr_cg.get_coverage(),
      reg_data_pattern_cg.get_coverage(),
      reg_ro_access_cg.get_coverage(),
      reg_burst_cg.get_coverage(),
      reg_reset_read_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "tx_length=%.1f%%, tx_bd_ctrl=%.1f%%, tx_moder=%.1f%%, tx_completion=%.1f%%",
      tx_pkt_length_cg.get_coverage(),
      tx_bd_ctrl_cg.get_coverage(),
      tx_moder_cg.get_coverage(),
      tx_completion_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "rx_length=%.1f%%, rx_completion=%.1f%%, rx_moder=%.1f%%, rx_bd_cnt=%.1f%%, rx_filter=%.1f%%",
      rx_pkt_length_cg.get_coverage(),
      rx_bd_completion_cg.get_coverage(),
      rx_moder_cg.get_coverage(),
      rx_bd_count_cg.get_coverage(),
      rx_addr_filter_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "hd_moder=%.1f%%, hd_collconf=%.1f%%, hd_completion=%.1f%%",
      hd_moder_cg.get_coverage(),
      hd_collconf_cg.get_coverage(),
      hd_tx_completion_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "fd_moder=%.1f%%, fd_ctrlmoder=%.1f%%, fd_tx_ctrl=%.1f%%",
      fd_moder_cg.get_coverage(),
      fd_ctrlmoder_cg.get_coverage(),
      fd_tx_ctrl_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "err_tx=%.1f%%, err_rx=%.1f%%, err_int=%.1f%%",
      err_tx_status_cg.get_coverage(),
      err_rx_status_cg.get_coverage(),
      err_int_source_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "sys_moder=%.1f%%, sys_mask=%.1f%%, sys_bd=%.1f%%",
      sys_moder_cg.get_coverage(),
      sys_int_mask_cg.get_coverage(),
      sys_bd_config_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "miim_cmd=%.1f%%, miim_moder=%.1f%%, miim_status=%.1f%%",
      miim_command_cg.get_coverage(),
      miim_moder_cg.get_coverage(),
      miim_status_cg.get_coverage()), UVM_LOW)

    `uvm_info("COVERAGE", $sformatf(
      "base_config=%.1f%%",
      base_config_cg.get_coverage()), UVM_LOW)
  endfunction : check_phase

endclass : eth_coverage
