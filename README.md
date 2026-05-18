Bidirectional CAN-to-Ethernet bridge IP core with dual-bus Wishbone interface.
Designed and verified at **IIITDM Kancheepuram** as part of the Final Year Project.

```
                    ┌─────────────────────────────────────────┐
                    │         can_eth_bridge_top               │
                    │                                         │
  CAN Controller ◄──┤  bridge_upstream   ──┐                   │──► Ethernet MAC
  (8-bit WB)       │  (CAN→ETH)         │ wb_arbiter         │    (32-bit WB)
                    │                    │ (CAN + ETH bus)    │
  CAN Controller ◄──┤  bridge_downstream ──┘                   │──► Ethernet MAC
  (8-bit WB)       │  (ETH→CAN)                              │    (32-bit WB)
                    │                                         │
  Host CPU ────────►┤  bridge_regs (WB slave, 32 registers)   │
                    │  can_id_filter (16-entry accept/reject)  │
                    │  can_tx_queue  (8-deep FIFO)             │
                    └─────────────────────────────────────────┘
```

- **Gateway mode** — CAN frames encapsulated with custom EtherType `0xCAFE`
- **Tunnel mode** — adds sequence number + timestamp (EtherType `0xCABE`)
- **16-entry CAN ID filter** — accept-list or reject-list mode
- **8-deep CAN TX queue** — absorbs CAN/ETH speed mismatch (1 Mbps vs 100 Mbps)
- **Dual Wishbone arbiter** — round-robin bus sharing for simultaneous upstream/downstream
- **Magic-byte validation** (`0xB1DE`) — downstream rejects non-bridge Ethernet frames
- **6 hardware counters** — CAN RX, ETH TX, ETH RX, CAN TX, filtered, errors

## Quick Start
```bash
# 1. Compile (QuestaSim)
cd verif/bridge/tb
make comp

# 2. Run a single test
make sim TESTNAME=upstream_basic_gw_test

# 3. Run full regression (25 tests)
make regress

# 4. Generate coverage report
make regress_report
```

See [INSTALL.md](INSTALL.md) for tool requirements.

## Repository Structure
```
.
├── rtl/
│   ├── bridge/                      Bridge IP RTL (9 modules)
│   │   ├── can_eth_bridge_top.v       Top-level bridge module
│   │   ├── bridge_upstream.v          Upstream FSM (CAN → ETH)
│   │   ├── bridge_downstream.v        Downstream FSM (ETH → CAN)
│   │   ├── bridge_regs.v             Host-accessible register file
│   │   ├── can_id_filter.v           16-entry CAN ID filter
│   │   ├── can_tx_queue.v            8-deep CAN TX FIFO
│   │   ├── wb_arbiter.v              Dual-bus Wishbone arbiter
│   │   ├── wb_adapter_32to8.v        32-to-8 bit bus width adapter
│   │   └── can_eth_bridge_defines.v  Global constants and FSM states
│   │
│   ├── ethmac/                      Ethernet MAC RTL (OpenCores, 27 files)
│   │   ├── eth_top.v                  MAC top-level
│   │   ├── eth_wishbone.v             Wishbone interface + DMA
│   │   ├── eth_rxethmac.v             RX datapath
│   │   ├── eth_txethmac.v             TX datapath
│   │   ├── eth_miim.v                 MII management
│   │   ├── eth_registers.v            MAC register file
│   │   └── ...                        (21 more supporting modules)
│   │
│   └── can/                         CAN controller RTL (OpenCores, 13 files)
│       ├── can_top.v                  CAN top-level (SJA1000)
│       ├── can_bsp.v                  Bit stream processor
│       ├── can_btl.v                  Bit timing logic
│       ├── can_registers.v            CAN register file
│       └── ...                        (9 more supporting modules)
│
├── verif/
│   ├── bridge/tb/                   Bridge UVM testbench (50 files)
│   │   ├── tb_bridge_top.sv           Testbench top module
│   │   ├── bridge_pkg.sv             UVM package (agents, env, tests)
│   │   ├── bridge_*_seq.sv           Test sequences
│   │   ├── *_test.sv                 25 test cases
│   │   ├── upstream_wave.do          QuestaSim waveform script
│   │   └── Makefile                  Build and regression targets
│   │
│   ├── can/tb/                      CAN controller UVM testbench
│   │   ├── top.sv                     Testbench top module
│   │   ├── cb_agent/                  CAN bus agent
│   │   ├── wb_agent/                  Wishbone agent & coverage
│   │   ├── seqs/                      UVM sequences
│   │   ├── tests/                     UVM tests (47 test cases)
│   │   └── run_complete_coverage.do   Regression script for 100% coverage
│   │
│   └── ethmac/tb/                   Ethernet MAC UVM testbench (101 files)
│       ├── tb_top.sv                  MAC testbench top module
│       ├── ethmac_pkg.sv             UVM package
│       ├── *_test.sv                 MAC test cases
│       ├── coverage.sv               MAC functional coverage
│       └── Makefile                  MAC build and regression targets
│
├── docs/
│   ├── CAN_ETH_Bridge_Spec.md        Functional specification
│   ├── CAN_ETH_Bridge_Design.md      Micro-architecture design document
│   ├── CAN_ETH_Bridge_TestPlan.xlsx  Full 25-test verification plan
│   └── ethmac/                      Ethernet MAC documentation (OpenCores)
│       ├── eth_speci.pdf              MAC functional specification
│       ├── eth_design_document.pdf    MAC design document
│       ├── ethernet_datasheet_OC_head.pdf
│       └── ethernet_product_brief_OC_head.pdf
│       └── ETHMAC_TestPlan.xlsx
│
├── .gitignore
├── .gitattributes
├── README.md
├── INSTALL.md
├── ethmac.core
└── LICENSE
```

## CAN Verification Coverage

The CAN verification suite uses UVM and includes 47 tests with detailed functional covergroups for 100% coverage closure.

| # | Covergroup | Maps to Test | What It Proves |
|---|---|---|---|
| **File: wb_can_coverage.sv (9 Covergroups)** | | | |
| 1 | `wb_can_cg` | WB-01 Single Access | Address ranges + R/W + data patterns |
| 2 | `wb_can_timing_cg` | WB-02 Consecutive | Back-to-back transaction timing |
| 3 | `wb_reg_access_cg` | REG-01 Reg Access | All 32 addresses × R/W (64 cross bins) |
| 4 | `wb_reg_reset_cg` | REG-02 Reg Reset | Key registers match datasheet defaults after reset |
| 5 | `wb_reg_ro_cg` | REG-03 Reg RO | Write attempts to all read-only register locations |
| 6 | `wb_reset_mode_lock_cg` | REG-04 ResetModeLock | Config reg writes in operating vs. reset mode |
| 7 | `wb_mode_switch_cg` | REG-05 Mode Switch | BasicCAN ↔ PeliCAN CDR.7 transitions |
| 8 | `wb_clk_div_cg` | REG-06 Clk Div | All 8 CDR[2:0] divider scaling bins |
| 9 | `wb_reset_recovery_cg` | WB-03 ResetStress | Post-reset bus recovery transactions |
| **File: can_tx_coverage.sv (9 Covergroups)** | | | |
| 10 | `can_tx_frame_format_cg`| TX-01, TX-02 | SFF vs. EFF frame format coverage |
| 11 | `can_tx_dlc_cg` | TX-04, TX-09 | All DLC values 0–8 covered |
| 12 | `can_tx_rtr_cg` | TX-03 | RTR bit set vs. cleared in transmitted frames |
| 13 | `can_tx_id_range_cg` | TX-01, TX-02, TX-09 | ID bins across low, mid, and max identifier ranges |
| 14 | `can_tx_cmd_cg` | TX-05, TX-05b, TX-07 | All CMR command bits exercised (TR, AT, SRR, SST) |
| 15 | `can_tx_data_pattern_cg`| TX-08 | Walking-1s, Walking-0s, and random data patterns |
| 16 | `can_tx_status_cg` | TX-01 to TX-09 | TBS, TCS, and interrupt status flags after TX |
| 17 | `can_tx_format_x_dlc_cg`| TX-04, TX-09 | Cross: frame format (SFF/EFF) × DLC (0–8) |
| 18 | `can_tx_format_x_rtr_cg`| TX-03 | Cross: frame format (SFF/EFF) × RTR bit |
| **File: can_rx_coverage.sv (6 Covergroups)** | | | |
| 19 | `can_rx_filter_mode_cg` | RX-01, RX-02 | Acceptance filter mode (Single vs Dual) |
| 20 | `can_rx_overrun_cg` | RX-05 | Data Overrun Status (DOS) bit detection |
| 21 | `can_rx_rmc_cg` | RX-06 | Receive Message Counter (RMC) depth bins |
| 22 | `can_rx_release_cg` | RX-07 | Release Receive Buffer (RRB) command |
| 23 | `can_rx_rtr_cg` | RX-08 | Remote Frame (RTR) vs Data Frame reception |
| 24 | `can_rx_format_cg` | RX-09 | Cross: RX Format (SFF/EFF) × DLC (0–8) |
| **File: can_prot_coverage.sv (3 Covergroups)** | | | |
| 25 | `can_prot_arb_cg` | ARB-01, 02 | SFF/EFF arbitration scenarios |
| 26 | `can_prot_alc_cg` | ALC-01 | Arbitration Lost Capture (ALC) bit locations |
| 27 | `can_prot_bit_stuff_cg` | STF-01 | Data patterns triggering bit stuffing |
| **File: can_err_coverage.sv (3 Covergroups)** | | | |
| 28 | `can_err_ecc_cg` | ERR Tests | ECC Capture: Bit, Form, Stuff, Other errors |
| 29 | `can_err_status_cg` | State Tests | Warning and Bus-Off status transitions |
| 30 | `can_err_counters_cg` | ERR Tests | TX/RX Error Counter ranges (Low, Warn, Pass) |

**Total: 30 Covergroups \| 281 Bins \| 281 Hits \| 100.00% Coverage**

## Tests
The verification suite contains **25 UVM tests** for the Bridge IP across 8 categories:

| Category | Tests | Coverage Target |
|----------|-------|-----------------|
| REG      | 2     | Register access and reset defaults |
| FLT      | 2     | CAN ID filter accept/reject |
| UP       | 5     | Upstream encapsulation (gateway, tunnel, EFF, DLC, filter) |
| DN       | 6     | Downstream decapsulation, tunnel, and error injection |
| SYS      | 6     | Queue, arbiter, E2E, full-duplex, stress |
| RST      | 1     | Mid-transaction reset recovery |
| MODE     | 2     | Gateway/tunnel switching, bridge disable |
| CNT      | 1     | Hardware counter verification |

Run a single test:
```bash
make sim TESTNAME=downstream_bad_magic_test
```

Run with waveforms:
```bash
make sim_waves TESTNAME=upstream_basic_gw_test
```

Expected regression output:
```
=== Regression complete: 25 saved, 0 missing ===
```

## Encapsulation Format
The bridge uses a custom Ethernet payload format:

| Word | Bits    | Field |
|------|---------|-------|
| 0–2  | —       | Standard Ethernet header (DST MAC, SRC MAC) |
| 3    | [31:16] | EtherType (`0xCAFE` gateway, `0xCABE` tunnel) |
| 3    | [15:8]  | Magic high byte (`0xB1`) |
| 3    | [7:0]   | Magic low byte (`0xDE`) |
| 4    | [31:8]  | CAN ID (11 or 29 bits) |
| 4    | [7:0]   | Version (`0x01`) |
| 5    | [31:24] | CAN ID lower + flags |
| 5    | [23:16] | DLC + control bits |
| 6–8  | —       | CAN payload data (up to 8 bytes, zero-padded) |

## Licence
Educational use — IIITDM Kancheepuram.
Ethernet MAC core: LGPL (OpenCores). CAN controller: LGPL (OpenCores).
