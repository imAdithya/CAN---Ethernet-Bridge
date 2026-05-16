# Makefile for CAN-Ethernet Bridge UVM Testbench (QuestaSim)

# --- Variables ---
TESTNAME ?= bridge_base_test
SEED     ?= $(shell powershell -Command "Get-Random -Minimum 1 -Maximum 999999")
VERBOSITY = UVM_HIGH
WORK_LIB = work
SIM_EXE  = bridge_sim
UCDB_FILE = $(TESTNAME)_$(SEED).ucdb
LOGFILE  = $(TESTNAME)_$(SEED).log

# Directory paths (relative to can ethernet bridge/tb/)
BRIDGE_RTL_DIR = ../rtl
ETH_RTL_DIR    = ../../rtl
ETH_TB_DIR     = ../../tb
CAN_RTL_DIR    = ../../rtl/can/trunk/rtl/verilog

# Code coverage: b=branch, c=condition, s=statement, f=FSM (toggle excluded — needs randomized stimulus)
COVER_OPTS = +cover=bcsf

# Include paths for headers
INCDIR = +incdir+$(BRIDGE_RTL_DIR) +incdir+$(ETH_RTL_DIR) +incdir+$(ETH_TB_DIR) +incdir+$(CAN_RTL_DIR)

# --- Test list (all 25 implemented tests) ---
TESTS = bridge_reg_access_test \
        bridge_reg_reset_test \
        filter_accept_test \
        filter_reject_test \
        counter_verify_test \
        mode_switch_test \
        bridge_disable_test \
        upstream_basic_gw_test \
        upstream_eff_test \
        upstream_dlc_sweep_test \
        upstream_tunnel_test \
        upstream_filter_drop_test \
        downstream_basic_gw_test \
        downstream_bad_ethertype_test \
        downstream_bad_dlc_test \
        downstream_backpressure_test \
        downstream_bad_magic_test \
        downstream_tunnel_test \
        queue_fill_drain_test \
        arbiter_contention_test \
        sys_upstream_e2e_test \
        sys_downstream_e2e_test \
        sys_fullduplex_test \
        sys_fullduplex_stress_test \
        mid_transaction_reset_test

# --- Targets ---

all: sim

# Compile RTL
comp_rtl:
	@echo --- Compiling Bridge RTL ---
	vlib $(WORK_LIB)
	vlog -work $(WORK_LIB) $(COVER_OPTS) $(INCDIR) $(BRIDGE_RTL_DIR)/*.v

# Compile TB (interfaces, package, top) — no code coverage on TB code
comp_tb: comp_rtl
	@echo --- Compiling Bridge TB ---
	vlog -work $(WORK_LIB) -sv $(INCDIR) \
		$(ETH_TB_DIR)/wishbone_slave_if.sv \
		$(ETH_TB_DIR)/wishbone_master_if.sv \
		can_wb_if.sv \
		mem_wb_if.sv
	vlog -work $(WORK_LIB) -sv $(INCDIR) \
		+incdir+$(ETH_TB_DIR) \
		bridge_pkg.sv
	vlog -work $(WORK_LIB) -sv $(INCDIR) \
		+incdir+$(ETH_TB_DIR) \
		tb_bridge_top.sv

# Full compilation
comp: comp_tb

# Optimize
opt: comp
	@echo --- Optimizing design ---
	vopt -work $(WORK_LIB) tb_bridge_top -o $(SIM_EXE) +access+r+w $(COVER_OPTS)

# Run single test
sim: opt
	@echo --- Running Test: $(TESTNAME) with SEED: $(SEED) ---
	vsim -c $(SIM_EXE) -coverage \
		+UVM_TESTNAME=$(TESTNAME) \
		+ntb_random_seed=$(SEED) \
		+UVM_VERBOSITY=$(VERBOSITY) \
		-do "coverage save -onexit $(UCDB_FILE); run -all; quit -f"

# Run without coverage (faster)
sim_nocov: opt
	@echo --- Running Test: $(TESTNAME) [NO COVERAGE] ---
	vsim -c $(SIM_EXE) \
		+UVM_TESTNAME=$(TESTNAME) \
		+ntb_random_seed=$(SEED) \
		+UVM_VERBOSITY=$(VERBOSITY) \
		-do "run -all; quit -f"

# Run with waveform dump
WAVE_FILE = $(TESTNAME)_$(SEED).wlf
sim_waves: opt
	@echo --- Running Test: $(TESTNAME) [WAVES ON] ---
	vsim $(SIM_EXE) -coverage \
		+UVM_TESTNAME=$(TESTNAME) \
		+ntb_random_seed=$(SEED) \
		+UVM_VERBOSITY=$(VERBOSITY) \
		-wlf $(WAVE_FILE) \
		-do "coverage save -onexit $(UCDB_FILE); run -all"

# --- Regression: run all implemented tests ---
regress: opt
	@echo === Running full regression ($(words $(TESTS)) tests) ===
	@powershell -Command " \
		$$tests = '$(TESTS)'.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries); \
		$$pass = 0; $$fail = 0; \
		foreach ($$t in $$tests) { \
			Write-Host '--- Running' $$t '---'; \
			vsim -c $(SIM_EXE) -coverage +UVM_TESTNAME=$$t +ntb_random_seed=random +UVM_VERBOSITY=UVM_MEDIUM -do ('coverage save -onexit ' + $$t + '.ucdb; run -all; quit -f'); \
			if (Test-Path ($$t + '.ucdb')) { $$pass++; Write-Host $$t ': UCDB saved' } else { $$fail++; Write-Host $$t ': UCDB MISSING' } \
		}; \
		Write-Host '=== Regression complete:' $$pass 'saved,' $$fail 'missing ===' \
	"

# --- Merge all UCDB files into one ---
merge:
	@echo --- Merging coverage data ---
	@powershell -Command " \
		$$ucdbs = Get-ChildItem -Filter '*.ucdb' | Where-Object { $$_.Name -ne 'merged_coverage.ucdb' } | ForEach-Object { $$_.Name }; \
		if ($$ucdbs.Count -eq 0) { Write-Error 'No UCDB files found'; exit 1 }; \
		$$cmd = 'vcover merge merged_coverage.ucdb ' + ($$ucdbs -join ' '); \
		Write-Host $$cmd; \
		Invoke-Expression $$cmd \
	"

# --- Generate HTML coverage report (DUT-only) ---
report: merge
	@echo --- Generating HTML coverage report ---
	vcover report -html -output covhtmlreport merged_coverage.ucdb
	@echo --- Report at covhtmlreport/index.html ---

# --- Generate text coverage report ---
report_txt: merge
	@echo --- Generating text coverage report ---
	vcover report -details merged_coverage.ucdb > coverage_report.txt
	@echo --- Report saved to coverage_report.txt ---

# --- Run regression + generate report ---
regress_report: regress report
	@echo === Full regression with coverage report complete ===

# Clean
clean:
	@echo --- Cleaning up ---
	if exist $(WORK_LIB) rmdir /s /q $(WORK_LIB)
	if exist transcript del /f /q transcript
	if exist *.log del /f /q *.log
	if exist *.wlf del /f /q *.wlf
	if exist *.ucdb del /f /q *.ucdb
	if exist *.txt del /f /q *.txt
	if exist *.bak del /f /q *.bak
	if exist *.vcd del /f /q *.vcd
	if exist *.lck del /f /q *.lck
	if exist covhtmlreport rmdir /s /q covhtmlreport

.PHONY: all comp_rtl comp_tb comp opt sim sim_nocov sim_waves regress merge report report_txt regress_report clean
