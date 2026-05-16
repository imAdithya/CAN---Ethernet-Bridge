//////////////////////////////////////////////////////////////////////
////                                                              ////
////  can_eth_bridge_defines.v                                    ////
////                                                              ////
////  Global defines, parameters, and constants for the           ////
////  CAN-Ethernet Bridge IP core.                                ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

//--------------------------------------------------------------
// Bridge Modes
//--------------------------------------------------------------
`define BRIDGE_MODE_GATEWAY  2'b01
`define BRIDGE_MODE_TUNNEL   2'b10

//--------------------------------------------------------------
// EtherTypes
//--------------------------------------------------------------
`define ETHERTYPE_GATEWAY    16'hCAFE
`define ETHERTYPE_TUNNEL     16'hCABE

//--------------------------------------------------------------
// Bridge Header Constants
//--------------------------------------------------------------
`define BRIDGE_MAGIC_HI      8'hB1
`define BRIDGE_MAGIC_LO      8'hDE
`define BRIDGE_VERSION       8'h01

//--------------------------------------------------------------
// CAN Controller Register Addresses (SJA1000 / OpenCores)
//--------------------------------------------------------------
`define CAN_REG_MODE         8'h00   // Mode register
`define CAN_REG_CMD          8'h01   // Command register
`define CAN_REG_STATUS       8'h02   // Status register
`define CAN_REG_IRQ          8'h03   // Interrupt register
`define CAN_REG_TXBUF_START  8'h10   // TX/RX buffer start (frame info)
`define CAN_REG_TXBUF_END    8'h1C   // TX/RX buffer end (data byte 7)

// Command register bits
`define CAN_CMD_TX_REQ       8'h01   // Transmit request
`define CAN_CMD_ABORT_TX     8'h02   // Abort transmission
`define CAN_CMD_REL_BUF      8'h04   // Release receive buffer
`define CAN_CMD_SELF_RX      8'h10   // Self-reception request

//--------------------------------------------------------------
// Upstream FSM States (CAN → ETH)
//--------------------------------------------------------------
`define UP_IDLE              4'd0
`define UP_READ_CAN          4'd1
`define UP_FILTER            4'd2
`define UP_ENCAP             4'd3
`define UP_WRITE_RAM         4'd4
`define UP_PROG_BD           4'd5
`define UP_WAIT_TX           4'd6
`define UP_RELEASE           4'd7

//--------------------------------------------------------------
// Downstream FSM States (ETH → CAN)
//--------------------------------------------------------------
`define DN_IDLE              4'd0
`define DN_READ_BD           4'd1
`define DN_READ_RAM          4'd2
`define DN_VALIDATE          4'd3
`define DN_DECAP             4'd4
`define DN_QUEUE_CHK         4'd5
`define DN_ENQUEUE           4'd6
`define DN_WRITE_CAN         4'd7
`define DN_WAIT_CAN_TX       4'd8
`define DN_FREE_BD           4'd9

//--------------------------------------------------------------
// Bridge Register Offsets (WB Slave Address Map)
//--------------------------------------------------------------
`define REG_BRIDGE_CTRL      8'h00   // [0] enable, [2:1] mode
`define REG_BRIDGE_STATUS    8'h04   // read-only status
`define REG_DST_MAC_HI       8'h08   // dst_mac[47:16]
`define REG_DST_MAC_LO       8'h0C   // {16'b0, dst_mac[15:0]}
`define REG_SRC_MAC_HI       8'h10   // src_mac[47:16]
`define REG_SRC_MAC_LO       8'h14   // {16'b0, src_mac[15:0]}
`define REG_FILTER_CTRL      8'h18   // [0] enable, [1] mode
`define REG_FILTER_TBL_BASE  8'h1C   // filter_table[0], +4 per entry
`define REG_FILTER_TBL_END   8'h58   // filter_table[15] = 0x1C + 15*4
`define REG_CNT_CAN_RX       8'h5C   // CAN frames received
`define REG_CNT_ETH_TX       8'h60   // ETH frames transmitted
`define REG_CNT_ETH_RX       8'h64   // ETH frames received
`define REG_CNT_CAN_TX       8'h68   // CAN frames transmitted
`define REG_CNT_FILTERED     8'h6C   // frames filtered/dropped
`define REG_CNT_ERRORS       8'h70   // error counter
`define REG_TUNNEL_SEQ       8'h74   // tunnel sequence number (RO)
`define REG_TX_BD_ADDR       8'h78   // TX buffer descriptor address
`define REG_RX_BD_ADDR       8'h7C   // RX buffer descriptor address

//--------------------------------------------------------------
// Parameters
//--------------------------------------------------------------
`define FILTER_DEPTH         16      // number of filter entries
`define QUEUE_DEPTH          8       // CAN TX queue depth
`define FRAME_WORDS          16      // 16 x 32-bit = 64 bytes max

// Timestamp prescaler: 50 MHz / 1000 = 50 kHz → 20 µs per tick
`define TIMESTAMP_PRESCALE   10'd999

//--------------------------------------------------------------
// Default Configuration (Hybrid — works without CPU)
//--------------------------------------------------------------
// Locally-administered MAC: 02:CA:FE:00:00:01
`define DEFAULT_SRC_MAC_HI   32'h02_CA_FE_00
`define DEFAULT_SRC_MAC_LO   32'h0000_0001
// Broadcast destination (any device receives)
`define DEFAULT_DST_MAC_HI   32'hFF_FF_FF_FF
`define DEFAULT_DST_MAC_LO   32'h0000_FFFF
// Bridge enabled, gateway mode
`define DEFAULT_BRIDGE_CTRL  32'h0000_0001
// Filter disabled (forward all)
`define DEFAULT_FILTER_CTRL  32'h0000_0000
// TX BD at ETH MAC offset 0x400 (BD index 0)
`define DEFAULT_TX_BD_ADDR   32'h0000_0400
// RX BD at ETH MAC offset 0x600 (first RX BD)
`define DEFAULT_RX_BD_ADDR   32'h0000_0600
