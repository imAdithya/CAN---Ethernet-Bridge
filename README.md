# CAN–Ethernet Bridge IP Core

Bidirectional CAN-to-Ethernet bridge IP core with dual-bus Wishbone interface.
Designed and verified at **IIITDM Chennai** as part of the Final Year Project.

## Bridge Overview

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

### Key Features

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
cd verif/tb
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
├── rtl/                          RTL source files
│   ├── can_eth_bridge_top.v        Top-level bridge module
│   ├── bridge_upstream.v           Upstream FSM (CAN → ETH)
│   ├── bridge_downstream.v        Downstream FSM (ETH → CAN)
│   ├── bridge_regs.v              Host-accessible register file
│   ├── can_id_filter.v            16-entry CAN ID filter
│   ├── can_tx_queue.v             8-deep CAN TX FIFO
│   ├── wb_arbiter.v               Dual-bus Wishbone arbiter
│   ├── wb_adapter_32to8.v         32-to-8 bit bus width adapter
│   └── can_eth_bridge_defines.v   Global constants and FSM states
│
├── verif/
│   ├── tb/                       UVM testbench sources
│   │   ├── tb_bridge_top.sv        Testbench top module
│   │   ├── bridge_pkg.sv          UVM package (agents, env, tests)
│   │   ├── bridge_*_seq.sv        Test sequences
│   │   ├── *_test.sv              25 test cases
│   │   ├── upstream_wave.do       QuestaSim upstream waveform script
│   │   ├── downstream_wave.do     QuestaSim downstream waveform script
│   │   └── Makefile               Build and regression targets
│   └── scripts/
│       └── Makefile.questa        Standalone QuestaSim Makefile
│
├── docs/
│   ├── CAN_ETH_Bridge_Spec.md      Functional specification
│   ├── CAN_ETH_Bridge_Design.md    Micro-architecture design document
│   ├── CAN_ETH_Bridge_TestPlan.xlsx  Full 25-test verification plan
│   └── figures/                      Architecture and waveform diagrams
│
├── scripts/                      Utility scripts (future)
│
├── .gitignore
├── .gitattributes
├── README.md
├── INSTALL.md
└── LICENSE
```

## Tests

The verification suite contains **25 UVM tests** across 8 categories:

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

Educational use — IIITDM Chennai.
Ethernet MAC core: LGPL (OpenCores). CAN controller: LGPL (OpenCores).
