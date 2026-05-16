# Installation Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| QuestaSim (or ModelSim) | 2024.1+ | RTL simulation and UVM |
| GNU Make | 4.0+ | Build automation |
| Python 3 | 3.8+ | Coverage report scripting (optional) |
| openpyxl | — | Test plan Excel editing (optional) |

## Tool Setup

### QuestaSim / ModelSim

1. Install QuestaSim 2024.1 or later (includes UVM 1.1d built-in)
2. Ensure `vlib`, `vlog`, `vsim`, `vopt`, and `vcover` are on your PATH:
   ```bash
   which vsim   # Linux/Mac
   where vsim   # Windows
   ```

### GNU Make (Windows)

On Windows, install Make via one of:
- **Chocolatey**: `choco install make`
- **MSYS2**: Comes with `mingw-w64` toolchain
- **Git for Windows**: Available as `mingw32-make`

## Building and Running

```bash
# Navigate to the testbench directory
cd verif/tb

# Compile all RTL and TB sources
make comp

# Run a single test
make sim TESTNAME=upstream_basic_gw_test

# Run with waveforms (GUI mode)
make sim_waves TESTNAME=downstream_basic_gw_test

# Run full regression (24 tests)
make regress

# Merge coverage and generate HTML report
make regress_report
# Report at: verif/tb/covhtmlreport/index.html
```

## Directory Path Configuration

The Makefile expects the following relative paths from `verif/tb/`:

```
BRIDGE_RTL_DIR = ../../rtl           # Bridge RTL
ETH_RTL_DIR    = ../../../../rtl     # Ethernet MAC RTL (if available)
ETH_TB_DIR     = ../../../../tb      # Ethernet MAC TB (for WB interfaces)
CAN_RTL_DIR    = ../../../../rtl/can/trunk/rtl/verilog  # CAN controller
```

Adjust `BRIDGE_RTL_DIR` in the Makefile if your directory layout differs.

## Standalone RTL Compilation (without UVM)

If you only want to check RTL syntax:
```bash
cd rtl
vlib work
vlog +incdir+. *.v
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `UVM package not found` | Ensure QuestaSim includes UVM 1.1d (`vsim -version`) |
| `uvm_hdl_force fails` | Use `-voptargs="+acc"` for mid-transaction reset test |
| `WB timeout errors` | Increase `#Xns` delays in test sequences |
| `Coverage = 0%` | Run via `make sim` (not `make sim_nocov`) |
