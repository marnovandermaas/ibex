//
// Generated by Bluespec Compiler, version 2017.07.A (build 1da80f1, 2017-07-21)
//
// On Thu Jul 18 14:51:20 BST 2019
//
//
// Ports:
// Name                         I/O  size props
// wrap64_getBase                 O    32
// wrap64_getBase_cap             I    93
//
// Combinational paths from inputs to outputs:
//   wrap64_getBase_cap -> wrap64_getBase
//
//

`ifdef BSV_ASSIGNMENT_DELAY
`else
  `define BSV_ASSIGNMENT_DELAY
`endif

`ifdef BSV_POSITIVE_RESET
  `define BSV_RESET_VALUE 1'b1
  `define BSV_RESET_EDGE posedge
`else
  `define BSV_RESET_VALUE 1'b0
  `define BSV_RESET_EDGE negedge
`endif

module module_wrap64_getBase(wrap64_getBase_cap,
			     wrap64_getBase);
  // value method wrap64_getBase
  input  [92 : 0] wrap64_getBase_cap;
  output [31 : 0] wrap64_getBase;

  // signals for module outputs
  wire [31 : 0] wrap64_getBase;

  // remaining internal signals
  wire [31 : 0] addBase__h52;
  wire [23 : 0] mask__h53;
  wire [9 : 0] x__h157;

  // value method wrap64_getBase
  assign wrap64_getBase =
	     { wrap64_getBase_cap[89:66] & mask__h53, 8'd0 } + addBase__h52 ;

  // remaining internal signals
  assign addBase__h52 =
	     { {22{x__h157[9]}}, x__h157 } << wrap64_getBase_cap[31:26] ;
  assign mask__h53 = 24'd16777215 << wrap64_getBase_cap[31:26] ;
  assign x__h157 = { wrap64_getBase_cap[1:0], wrap64_getBase_cap[17:10] } ;
endmodule  // module_wrap64_getBase
