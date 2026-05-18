# Makefile for Ethernet MAC UVM Testbench (QuestaSim - Final with Coverage Report)

# --- Variables ---
TESTNAME ?= base_test
SEED     ?= $(shell powershell -Command "Get-Random -Minimum 1 -Maximum 999999")
VERBOSITY = UVM_HIGH
WORK_LIB = work
SIM_EXE  = ethmac_sim
UCDB_FILE = $(TESTNAME)_$(SEED).ucdb
REPORT_FILE = coverage_report_$(TESTNAME)_$(SEED).txt
LOGFILE  = $(TESTNAME)_$(SEED).log

# Directory containing RTL design files
RTL_DIR = ../rtl

# Code coverage options: b=branch, c=condition, s=statement, x=toggle, f=FSM
COVER_OPTS = +cover=bcstf

# Include path for RTL headers (timescale.v, ethmac_defines.v, etc.)
INCDIR = +incdir+$(RTL_DIR)

# --- Targets ---

# Default target
all: sim

# Compilation target (with code coverage)
comp:
	@echo --- Creating library and compiling ---
	vlib $(WORK_LIB)
	vlog -work $(WORK_LIB) $(COVER_OPTS) $(INCDIR) $(RTL_DIR)/*.v
	vlog -work $(WORK_LIB) $(COVER_OPTS) $(INCDIR) *.v
	vlog -work $(WORK_LIB) -sv $(COVER_OPTS) $(INCDIR) wishbone_slave_if.sv wishbone_master_if.sv mii_if.sv wishbone_memory_model.sv
	vlog -work $(WORK_LIB) -sv $(COVER_OPTS) $(INCDIR) ethmac_pkg.sv
	vlog -work $(WORK_LIB) -sv $(COVER_OPTS) $(INCDIR) tb_top.sv

# Optimization target (preserve coverage)
opt: comp
	@echo --- Optimizing design ---
	vopt -work $(WORK_LIB) tb_top -o $(SIM_EXE) +access+r+w $(COVER_OPTS)

#vopt -work $(WORK_LIB) tb_top -o $(SIM_EXE) +acc

# Simulation target (with coverage saving and reporting)
sim: opt
	@echo --- Running Test: $(TESTNAME) with SEED: $(SEED) ---
	vsim -c $(SIM_EXE) -coverage +UVM_TESTNAME=$(TESTNAME) +ntb_random_seed=$(SEED) +UVM_VERBOSITY=$(VERBOSITY) \
	-do "coverage save -onexit $(UCDB_FILE); run -all; quit -f"

# Simulation without coverage (faster, for quick checks)
sim_nocov: opt
	@echo --- Running Test: $(TESTNAME) with SEED: $(SEED) [NO COVERAGE] ---
	vsim -c $(SIM_EXE) +UVM_TESTNAME=$(TESTNAME) +ntb_random_seed=$(SEED) +UVM_VERBOSITY=$(VERBOSITY) \
	-do "run -all; quit -f"

# Simulation with waveform dump (generates .wlf for QuestaSim viewing)
WAVE_FILE = $(TESTNAME)_$(SEED).wlf
sim_waves: opt
	@echo --- Running Test: $(TESTNAME) with SEED: $(SEED) [WAVES ON] ---
	vsim $(SIM_EXE) -coverage +UVM_TESTNAME=$(TESTNAME) +ntb_random_seed=$(SEED) +UVM_VERBOSITY=$(VERBOSITY) \
	-wlf $(WAVE_FILE) \
	-do "coverage save -onexit $(UCDB_FILE); do wave.do; run -all"
	@echo --- Waves saved to $(WAVE_FILE) ---

# Clean target
clean:
	@echo --- Cleaning up ---
	if exist $(WORK_LIB) rmdir /s /q $(WORK_LIB)
	if exist transcript del /f /q transcript
	if exist *.log del /f /q *.log
	if exist *.wlf del /f /q *.wlf
	if exist *.ucdb del /f /q *.ucdb
	if exist *.txt del /f /q *.txt
	if exist *.bak del /f /q *.bak
	if exist *.bin del /f /q *.bin
	if exist *.vcd del /f /q *.vcd
	if exist *.lck del /f /q *.lck

.PHONY: all comp opt sim sim_nocov sim_waves clean
