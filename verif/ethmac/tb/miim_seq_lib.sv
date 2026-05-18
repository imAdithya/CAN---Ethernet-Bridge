// miim_seq_lib.sv - MIIM (MII Management) Sequence Library using raw Wishbone access

//============================================================================
// MIIM READ/WRITE SEQUENCE (MIIM-01)
//============================================================================
class miim_read_write_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(miim_read_write_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam CMD_RSTAT     = 32'h02;
  localparam CMD_WCTRLDATA = 32'h04;
  localparam PHY_ADDR = 5'd1;

  typedef struct {
    int       reg_addr;
    bit [15:0] wr_data;
    string    name;
  } miim_test_t;

  host_agent_config m_host_cfg;

  function new(string name = "miim_read_write_seq");
    super.new(name);
  endfunction

  task wait_miim_done();
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h02)) return;
    end
    `uvm_error(get_type_name(), "MIIM BUSY timeout!")
  endtask

  task miim_write(int phy_addr, int reg_addr, bit [15:0] data);
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h34; write_reg_seq.data = {16'h0, data}; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_WCTRLDATA; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  task miim_read(int phy_addr, int reg_addr, output bit [15:0] data);
    uvm_status_e st;
    logic [31:0] rdata;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_RSTAT; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    data = rdata[15:0];
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    bit [15:0] rd_data;
    logic [31:0] status_val;
    miim_test_t tests[];
    tests = new[5];
    tests[0] = '{reg_addr: 2,  wr_data: 16'h1234, name: "PHY ID1 Reg (2)"};
    tests[1] = '{reg_addr: 4,  wr_data: 16'hABCD, name: "Advertise Reg (4)"};
    tests[2] = '{reg_addr: 16, wr_data: 16'h5555, name: "Vendor Reg (16)"};
    tests[3] = '{reg_addr: 20, wr_data: 16'hFFFF, name: "Vendor Reg (20)"};
    tests[4] = '{reg_addr: 31, wr_data: 16'hBEEF, name: "Max Reg Addr (31)"};
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("MIIM-01: MIIM Read/Write Test - %0d register tests", tests.size()), UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")

    // Configure MIIM clock divider via RAL
    write_reg_seq.addr = 32'h28; write_reg_seq.data = 32'h0000_000A; write_reg_seq.start(m_sequencer);
    #500ns;

    // Verify MIIM not busy initially
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status_val = read_reg_seq.data;
    if (status_val & 32'h02)
      `uvm_error(get_type_name(), $sformatf("MIIM BUSY at start (status=0x%08h)", status_val))
    else
      `uvm_info(get_type_name(), "MIIM not busy at start - OK", UVM_LOW)

    // Write then Read-back for each test register
    foreach (tests[i]) begin
      `uvm_info(get_type_name(), $sformatf("Test %0d: %s - Write 0x%04h to PHY %0d, Reg %0d",
        i, tests[i].name, tests[i].wr_data, PHY_ADDR, tests[i].reg_addr), UVM_LOW)
      miim_write(PHY_ADDR, tests[i].reg_addr, tests[i].wr_data);
      miim_read(PHY_ADDR, tests[i].reg_addr, rd_data);
      `uvm_info(get_type_name(), $sformatf("Test %0d: Write 0x%04h, Read 0x%04h", i, tests[i].wr_data, rd_data), UVM_LOW)
    end

    // Read PHY Status Reg (1) default value
    miim_read(PHY_ADDR, 1, rd_data);
    `uvm_info(get_type_name(), $sformatf("PHY Status Reg (1) default = 0x%04h", rd_data), UVM_LOW)

    `uvm_info(get_type_name(), $sformatf("MIIM-01: All %0d stimulus sequences completed", tests.size()), UVM_LOW)
  endtask : body
endclass : miim_read_write_seq

//============================================================================
// MIIM WALKING ONE SEQUENCE (MIIM-02)
//============================================================================
class miim_walking_one_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(miim_walking_one_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam CMD_RSTAT     = 32'h02;
  localparam CMD_WCTRLDATA = 32'h04;
  localparam PHY_ADDR      = 5'd1;
  localparam TEST_REG      = 5'd2;

  host_agent_config m_host_cfg;

  function new(string name = "miim_walking_one_seq");
    super.new(name);
  endfunction

  task wait_miim_done();
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h02)) return;
    end
    `uvm_error(get_type_name(), "MIIM BUSY timeout!")
  endtask

  task miim_write_with_status(int phy_addr, int reg_addr, bit [15:0] data);
    logic [31:0] status;
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h34; write_reg_seq.data = {16'h0, data}; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_WCTRLDATA; write_reg_seq.start(m_sequencer);
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (status & 32'h02) begin
      `uvm_info(get_type_name(), "MIISTATUS.Busy=1 during write - OK", UVM_MEDIUM)
    end
    wait_miim_done();
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (status & 32'h02) `uvm_error(get_type_name(), "MIISTATUS.Busy still set after write!")
    if (status[2]) `uvm_error(get_type_name(), "MIISTATUS.Nvalid set unexpectedly!")
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  task miim_read_with_status(int phy_addr, int reg_addr, output bit [15:0] data);
    logic [31:0] status, rdata;
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_RSTAT; write_reg_seq.start(m_sequencer);
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (status & 32'h02) begin
      `uvm_info(get_type_name(), "MIISTATUS.Busy=1 during read - OK", UVM_MEDIUM)
    end
    wait_miim_done();
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (status & 32'h02) `uvm_error(get_type_name(), "MIISTATUS.Busy still set after read!")
    if (status[2]) `uvm_error(get_type_name(), "MIISTATUS.Nvalid set unexpectedly!")
    read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    data = rdata[15:0];
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    bit [15:0] pattern, rd_data;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "MIIM-02: Walking Ones Test - 16 patterns", UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")

    write_reg_seq.addr = 32'h28; write_reg_seq.data = 32'h0000_000A; write_reg_seq.start(m_sequencer);
    #500ns;

    for (int bit_pos = 0; bit_pos < 16; bit_pos++) begin
      pattern = 16'h1 << bit_pos;
      `uvm_info(get_type_name(), $sformatf("Bit %0d: Write 0x%04h to PHY %0d, Reg %0d",
        bit_pos, pattern, PHY_ADDR, TEST_REG), UVM_LOW)
      miim_write_with_status(PHY_ADDR, TEST_REG, pattern);
      miim_read_with_status(PHY_ADDR, TEST_REG, rd_data);
      `uvm_info(get_type_name(), $sformatf("Bit %0d: Write 0x%04h, Read 0x%04h", bit_pos, pattern, rd_data), UVM_LOW)
    end

  endtask : body
endclass : miim_walking_one_seq

//============================================================================
// MIIM SCAN STATUS SEQUENCE (MIIM-03)
//============================================================================
class miim_scan_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(miim_scan_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam CMD_SCANSTAT  = 32'h01;
  localparam CMD_RSTAT     = 32'h02;
  localparam CMD_WCTRLDATA = 32'h04;
  localparam PHY_ADDR      = 5'd1;
  localparam TEST_REG      = 5'd2;

  host_agent_config m_host_cfg;

  function new(string name = "miim_scan_seq");
    super.new(name);
  endfunction

  task wait_miim_done();
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h02)) return;
    end
    `uvm_error(get_type_name(), "MIIM BUSY timeout!")
  endtask

  task miim_write(int phy_addr, int reg_addr, bit [15:0] data);
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h34; write_reg_seq.data = {16'h0, data}; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_WCTRLDATA; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  task wait_nvalid_clear(output logic [31:0] final_status);
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h04)) begin final_status = status; return; end
    end
    `uvm_error(get_type_name(), "Nvalid clear timeout!")
    final_status = status;
  endtask

  task wait_scan_data(bit [15:0] expected, output bit [15:0] actual);
    logic [31:0] rdata;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #500ns;
      read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
      actual = rdata[15:0];
      if (actual == expected) return;
    end
    `uvm_error(get_type_name(), $sformatf("Scan data timeout! Expected 0x%04h, got 0x%04h", expected, actual))
  endtask

  virtual task body();
    logic [31:0] status, rdata;
    bit [15:0] rd_data;
    bit [15:0] initial_val = 16'hA5A5;
    bit [15:0] changed_val = 16'h5A5A;
    uvm_status_e st;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "MIIM-03: Scan Status Test", UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")

    write_reg_seq.addr = 32'h28; write_reg_seq.data = 32'h0000_000A; write_reg_seq.start(m_sequencer);
    #500ns;

    // Phase 1: Write initial value
    miim_write(PHY_ADDR, TEST_REG, initial_val);

    // Phase 2: Enable ScanStat
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (TEST_REG << 8) | PHY_ADDR; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_SCANSTAT; write_reg_seq.start(m_sequencer);

    // Phase 3: Check Nvalid=1, Busy=1
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (status[2]) begin
      `uvm_info(get_type_name(), $sformatf("MIISTATUS=0x%0h - Nvalid=1 at start - OK", status), UVM_LOW)
    end
    if (status[1]) begin
      `uvm_info(get_type_name(), "Busy=1 during scan - OK", UVM_LOW)
    end else
      `uvm_error(get_type_name(), "Busy=0 during scan - UNEXPECTED!")

    // Phase 4: Wait for Nvalid to clear
    wait_nvalid_clear(status);


    // Phase 5: Verify scanned data
    read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    rd_data = rdata[15:0];
    if (rd_data == initial_val) begin
      `uvm_info(get_type_name(), $sformatf("Scanned 0x%04h matches - OK", rd_data), UVM_LOW)
    end else
      `uvm_error(get_type_name(), $sformatf("Scanned 0x%04h != expected 0x%04h", rd_data, initial_val))

    // Phase 6: Change PHY value, verify scan detects it
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    miim_write(PHY_ADDR, TEST_REG, changed_val);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_SCANSTAT; write_reg_seq.start(m_sequencer);
    wait_scan_data(changed_val, rd_data);
    if (rd_data == changed_val) begin
      `uvm_info(get_type_name(), $sformatf("Scan detected change to 0x%04h - OK", rd_data), UVM_LOW)
    end

    // Phase 7: Disable ScanStat
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (!status[1]) begin
      `uvm_info(get_type_name(), "Busy=0 after scan disabled - OK", UVM_LOW)
    end else
      `uvm_error(get_type_name(), "Busy still set after scan disabled!")

  endtask : body
endclass : miim_scan_seq

//============================================================================
// MIIM NO PREAMBLE SEQUENCE (MIIM-04)
//============================================================================
class miim_no_preamble_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(miim_no_preamble_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam CMD_RSTAT     = 32'h02;
  localparam CMD_WCTRLDATA = 32'h04;
  localparam PHY_ADDR      = 5'd1;

  host_agent_config m_host_cfg;

  function new(string name = "miim_no_preamble_seq");
    super.new(name);
  endfunction

  task wait_miim_done();
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h02)) return;
    end
    `uvm_error(get_type_name(), "MIIM BUSY timeout!")
  endtask

  task miim_write(int phy_addr, int reg_addr, bit [15:0] data);
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h34; write_reg_seq.data = {16'h0, data}; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_WCTRLDATA; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  task miim_read(int phy_addr, int reg_addr, output bit [15:0] data);
    uvm_status_e st;
    logic [31:0] rdata;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_RSTAT; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    data = rdata[15:0];
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    bit [15:0] rd_data;
    typedef struct {
      int       reg_addr;
      bit [15:0] wr_data;
      string    name;
    } test_t;

    test_t nopre_tests[];
    nopre_tests = new[3];
    nopre_tests[0] = '{reg_addr: 3,  wr_data: 16'hDEAD, name: "Reg 3"};
    nopre_tests[1] = '{reg_addr: 10, wr_data: 16'hCAFE, name: "Reg 10"};
    nopre_tests[2] = '{reg_addr: 25, wr_data: 16'hF00D, name: "Reg 25"};
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "MIIM-04: No Preamble Test", UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")

    // Phase 1: Set MIIMODER with NoPre=1 (bit 8) and ClkDiv=10
    write_reg_seq.addr = 32'h28; write_reg_seq.data = 32'h0000_010A; write_reg_seq.start(m_sequencer);
    #500ns;

    // Phase 2: Write/Read with NoPre=1
    foreach (nopre_tests[i]) begin
      `uvm_info(get_type_name(), $sformatf("NoPre Write: %s = 0x%04h", nopre_tests[i].name, nopre_tests[i].wr_data), UVM_LOW)
      miim_write(PHY_ADDR, nopre_tests[i].reg_addr, nopre_tests[i].wr_data);
      miim_read(PHY_ADDR, nopre_tests[i].reg_addr, rd_data);
      `uvm_info(get_type_name(), $sformatf("NoPre Read:  %s = 0x%04h (expected 0x%04h)",
        nopre_tests[i].name, rd_data, nopre_tests[i].wr_data), UVM_LOW)
    end

    // Phase 3: Switch back to NoPre=0
    write_reg_seq.addr = 32'h28; write_reg_seq.data = 32'h0000_000A; write_reg_seq.start(m_sequencer);
    #500ns;
    miim_write(PHY_ADDR, 5, 16'h1357);
    miim_read(PHY_ADDR, 5, rd_data);
    `uvm_info(get_type_name(), $sformatf("WithPre Read: Reg 5 = 0x%04h (expected 0x1357)", rd_data), UVM_LOW)

  endtask : body
endclass : miim_no_preamble_seq

//============================================================================
// MIIM CLOCK DIVIDER SEQUENCE (MIIM-05)
//============================================================================
class miim_divider_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(miim_divider_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam CMD_RSTAT     = 32'h02;
  localparam CMD_WCTRLDATA = 32'h04;
  localparam PHY_ADDR      = 5'd1;
  localparam TEST_REG      = 5'd4;

  host_agent_config m_host_cfg;

  function new(string name = "miim_divider_seq");
    super.new(name);
  endfunction

  task wait_miim_done();
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 10000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h02)) return;
    end
    `uvm_error(get_type_name(), "MIIM BUSY timeout!")
  endtask

  task miim_write(int phy_addr, int reg_addr, bit [15:0] data);
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h34; write_reg_seq.data = {16'h0, data}; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_WCTRLDATA; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  task miim_read(int phy_addr, int reg_addr, output bit [15:0] data);
    uvm_status_e st;
    logic [31:0] rdata;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_RSTAT; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    data = rdata[15:0];
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    bit [15:0] rd_data;
    typedef struct {
      int       divider;
      bit [15:0] wr_data;
      string    name;
    } div_test_t;

    div_test_t tests[];
    tests = new[5];
    tests[0] = '{divider: 2,   wr_data: 16'h1111, name: "Min (div=2)"};
    tests[1] = '{divider: 5,   wr_data: 16'h2222, name: "Small (div=5)"};
    tests[2] = '{divider: 10,  wr_data: 16'h3333, name: "Medium (div=10)"};
    tests[3] = '{divider: 50,  wr_data: 16'h4444, name: "Large (div=50)"};
    tests[4] = '{divider: 255, wr_data: 16'h5555, name: "Max (div=255)"};
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), $sformatf("MIIM-05: Clock Divider Test - %0d settings", tests.size()), UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")

    foreach (tests[i]) begin
      write_reg_seq.addr = 32'h28; write_reg_seq.data = tests[i].divider; write_reg_seq.start(m_sequencer);
      #500ns;
      `uvm_info(get_type_name(), $sformatf("Test %0d: %s - Write 0x%04h", i, tests[i].name, tests[i].wr_data), UVM_LOW)
      miim_write(PHY_ADDR, TEST_REG, tests[i].wr_data);
      miim_read(PHY_ADDR, TEST_REG, rd_data);
      `uvm_info(get_type_name(), $sformatf("Test %0d: %s - Read 0x%04h (expected 0x%04h)",
        i, tests[i].name, rd_data, tests[i].wr_data), UVM_LOW)
    end

  endtask : body
endclass : miim_divider_seq

//============================================================================
// MIIM ERROR INJECTION SEQUENCE (MIIM-06)
//============================================================================
class miim_error_seq extends uvm_sequence #(wishbone_transaction);
  `uvm_object_utils(miim_error_seq)
  `uvm_declare_p_sequencer(host_sequencer)
  reg_write_seq write_reg_seq;
  reg_read_seq  read_reg_seq;

  localparam CMD_RSTAT     = 32'h02;
  localparam CMD_WCTRLDATA = 32'h04;
  localparam VALID_PHY     = 5'd1;
  localparam INVALID_PHY   = 5'd31;

  host_agent_config m_host_cfg;

  function new(string name = "miim_error_seq");
    super.new(name);
  endfunction

  task wait_miim_done();
    logic [31:0] status;
    uvm_status_e st;
    for (int i = 0; i < 5000; i++) begin
      #200ns;
      read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
      if (!(status & 32'h02)) return;
    end
    `uvm_error(get_type_name(), "MIIM BUSY timeout!")
  endtask

  task miim_write(int phy_addr, int reg_addr, bit [15:0] data);
    uvm_status_e st;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h34; write_reg_seq.data = {16'h0, data}; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_WCTRLDATA; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  task miim_read(int phy_addr, int reg_addr, output bit [15:0] data);
    uvm_status_e st;
    logic [31:0] rdata;
    write_reg_seq.addr = 32'h30; write_reg_seq.data = (reg_addr << 8) | phy_addr; write_reg_seq.start(m_sequencer);
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = CMD_RSTAT; write_reg_seq.start(m_sequencer);
    wait_miim_done();
    read_reg_seq.addr = 32'h38; read_reg_seq.start(m_sequencer); rdata = read_reg_seq.data;
    data = rdata[15:0];
    write_reg_seq.addr = 32'h2C; write_reg_seq.data = 32'h0; write_reg_seq.start(m_sequencer);
  endtask

  virtual task body();
    bit [15:0] rd_data;
    logic [31:0] status;
    uvm_status_e st;
    write_reg_seq = reg_write_seq::type_id::create("write_reg_seq");
    read_reg_seq  = reg_read_seq::type_id::create("read_reg_seq");

    `uvm_info(get_type_name(), "MIIM-06: Error Injection Test", UVM_LOW)

    if (!uvm_config_db#(host_agent_config)::get(null, "uvm_test_top.m_env.m_host_agent*", "config", m_host_cfg))
      `uvm_fatal("SEQ", "Cannot get host_agent_config")

    write_reg_seq.addr = 32'h28; write_reg_seq.data = 32'h0000_000A; write_reg_seq.start(m_sequencer);
    #500ns;

    // Phase 1: Write to valid PHY
    miim_write(VALID_PHY, 3, 16'hBEEF);

    // Phase 2: Read from non-existent PHY
    miim_read(INVALID_PHY, 3, rd_data);
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (!status[1])
      `uvm_info(get_type_name(), "Busy cleared after invalid PHY read - OK", UVM_LOW)
    else
      `uvm_error(get_type_name(), "Busy still set after invalid PHY read!")
    `uvm_info(get_type_name(), $sformatf("Invalid PHY read data = 0x%04h", rd_data), UVM_LOW)

    // Phase 3: Write to non-existent PHY
    miim_write(INVALID_PHY, 3, 16'hDEAD);
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    if (!status[1])
      `uvm_info(get_type_name(), "Busy cleared after invalid PHY write - OK", UVM_LOW)
    else
      `uvm_error(get_type_name(), "Busy still set after invalid PHY write!")

    // Phase 4: Read Status Reg from non-existent PHY (LinkFail)
    miim_read(INVALID_PHY, 1, rd_data);
    read_reg_seq.addr = 32'h3C; read_reg_seq.start(m_sequencer); status = read_reg_seq.data;
    `uvm_info(get_type_name(), $sformatf("MIISTATUS after invalid Status read = 0x%0h (LinkFail=%0b)", status, status[0]), UVM_LOW)

    // Phase 5: Verify valid PHY still works
    miim_read(VALID_PHY, 3, rd_data);
    if (rd_data == 16'hBEEF) begin
      `uvm_info(get_type_name(), $sformatf("Recovery: Valid PHY read 0x%04h matches - OK", rd_data), UVM_LOW)
    end else
      `uvm_error(get_type_name(), $sformatf("Recovery: Valid PHY read 0x%04h != expected 0xBEEF", rd_data))

  endtask : body
endclass : miim_error_seq
