//
// Generated by Bluespec Compiler, version 2017.07.A (build 1da80f1, 2017-07-21)
//
// On Thu Jul 18 14:51:20 BST 2019
//
//
// Ports:
// Name                         I/O  size props
// wrap64_setFlags                O    93
// wrap64_setFlags_cap            I    93
// wrap64_setFlags_flags          I     1
//
// Combinational paths from inputs to outputs:
//   (wrap64_setFlags_cap, wrap64_setFlags_flags) -> wrap64_setFlags
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

module module_wrap64_setFlags(wrap64_setFlags_cap,
			      wrap64_setFlags_flags,
			      wrap64_setFlags);
  // value method wrap64_setFlags
  input  [92 : 0] wrap64_setFlags_cap;
  input  wrap64_setFlags_flags;
  output [92 : 0] wrap64_setFlags;

  // signals for module outputs
  wire [92 : 0] wrap64_setFlags;

  // value method wrap64_setFlags
  assign wrap64_setFlags =
	     { wrap64_setFlags_cap[92:38],
	       wrap64_setFlags_flags,
	       wrap64_setFlags_cap[36:0] } ;
endmodule  // module_wrap64_setFlags
