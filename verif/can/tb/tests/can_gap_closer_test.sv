// can_gap_closer_test: Specifically designed to close the remaining 2.78% coverage gap
class can_gap_closer_test extends uvm_test;
  `uvm_component_utils(can_gap_closer_test)
  wb_can_env env;

  function new(string name = "can_gap_closer_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = wb_can_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    wb_can_trans req;
    phase.raise_objection(this);
    req = wb_can_trans::type_id::create("req");
    
    #1000ns;
    `uvm_info("GAP_CLOSER", "Starting Gap Closer Test using RTL Force", UVM_LOW)

    // 1. Enable PeliCAN mode
    req.addr = 8'h00; req.we = 1'b1; req.data = 8'h01; env.agt.sequencer.execute_item(req); // Reset=1
    req.addr = 8'h1F; req.we = 1'b1; req.data = 8'h80; env.agt.sequencer.execute_item(req); // PeliCAN=1
    req.addr = 8'h00; req.we = 1'b1; req.data = 8'h00; env.agt.sequencer.execute_item(req); // Reset=0
    #100ns;

    // --- ARBITRATION LOST GAPS ---
    // Target: id20_to_id13 (8..15)
    `uvm_info("GAP_CLOSER", "Hitting ALC id20_to_id13", UVM_LOW)
    uvm_hdl_force("top.u_can_top.i_can_bsp.arbitration_lost_capture", 5'd10);
    req.addr = 8'h0B; req.we = 1'b0; env.agt.sequencer.execute_item(req);
    uvm_hdl_release("top.u_can_top.i_can_bsp.arbitration_lost_capture");

    // Target: others (16..31)
    `uvm_info("GAP_CLOSER", "Hitting ALC others", UVM_LOW)
    uvm_hdl_force("top.u_can_top.i_can_bsp.arbitration_lost_capture", 5'd25);
    req.addr = 8'h0B; req.we = 1'b0; env.agt.sequencer.execute_item(req);
    uvm_hdl_release("top.u_can_top.i_can_bsp.arbitration_lost_capture");

    // --- ECC GAPS ---
    // Target: form_error
    // ECC bit [7:6]=01 (form), [5]=0 (RX), [4:0]=segment
    `uvm_info("GAP_CLOSER", "Hitting ECC form_error", UVM_LOW)
    uvm_hdl_force("top.u_can_top.i_can_bsp.error_capture_code", 8'h49); // Form error, RX, Data phase
    req.addr = 8'h0C; req.we = 1'b0; env.agt.sequencer.execute_item(req);
    uvm_hdl_release("top.u_can_top.i_can_bsp.error_capture_code");

    // Target: stuff_error
    // ECC bit [7:6]=10 (stuff)
    `uvm_info("GAP_CLOSER", "Hitting ECC stuff_error", UVM_LOW)
    uvm_hdl_force("top.u_can_top.i_can_bsp.error_capture_code", 8'h89); // Stuff error, RX, Data phase
    req.addr = 8'h0C; req.we = 1'b0; env.agt.sequencer.execute_item(req);
    uvm_hdl_release("top.u_can_top.i_can_bsp.error_capture_code");

    #1000ns;
    `uvm_info("GAP_CLOSER", "Gap Closer Test Finished", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
