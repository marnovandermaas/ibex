
// should this really just be a "wrapper" for all the functions that i get?
// in id stage, i set all the inputs for each of the function wrappers
// these function wrappers are just ways of selecting which function i want to apply to 
// the capability
// ANSWER: this isn't really possible, since instructions might need to read many different
// values from each capability.
// could potentially pass in a vector of what i want done, but that might add unnecessary
// complexity to understanding how the system works

// the inputs should be the max size of any input that i need
// for inputs that are smaller than the max size, the upper bits should be 0


// file structure if planning on having all the functions here:
/*
  top: variable declarations



  bottom: all the module instantiations
*/

//

// TODO add these to makefile instead of here
`define CAP_SIZE 93
`define EXCEPTION_SIZE 22
`define OTYPE_SIZE 4
`define REGS_PER_QUARTER 4
`define INTEGER_SIZE 32
`define FLAG_SIZE 1
`define PERMS_SIZE 31
`define LENGTH_SIZE 33
`define OFFSET_SIZE 32
`define BASE_SIZE 32
`define IMM_SIZE 12
`define PERMIT_SEAL_INDEX 7
`define PERMIT_UNSEAL_INDEX 9
`define PERMIT_EXECUTE_INDEX 1
`define PERMIT_CCALL_INDEX 8
`define PERMIT_GLOBAL_INDEX 0
`define MIN_INSTR_BYTES 2
// TODO change this back to 'hb, changed here to agree with piccolo
`define MAX_OTYPE `INTEGER_SIZE'hc


/*
parameter CAP_SIZE  = 93;
parameter OTYPE_SIZE = 4;
parameter REGS_PER_QUARTER = 4;
parameter INTEGER_SIZE = 32;
parameter FLAG_SIZE = 1;
parameter PERMS_SIZE = 31;
parameter LENGTH_SIZE = 33;
parameter OFFSET_SIZE = 32;
parameter BASE_SIZE = 32;
parameter EXCEPTION_SIZE = 22;
*///


// TODO: remove all adds in this file and use connections to the ALU instead.
//       may improve area required for the design

// ask:
// what do i do if i try to do a capability instruction on a non-capability operand?
//    each instr tells you what to do, if it doesn't then you just do what the instr says
//    and don't care what you've done it on
// explain coprocessor 2 exception?
//    MIPS-only, look at CHERI-RISCV sail definitions under the quick reference
// cheri risc-v page 151 - top (93-32 = 61) bits of null cap are not all 0
//    we need to pass all legacy reads/writes through getaddr or nullwithaddr in order
//    to put them in the registers or for them to be valid

// TODO:
// two ways of implementing the last point above:
/*    I can pass all the integer writes from here through a nullwithaddr before they leave this
        unit. This will then mean that I need to pass all the other writes to registers also through
        their own nullwithaddr before i write them to registers
      Alternatively, I can pass integer writes from here as just normal integer writes. I can mux these
        normal integer writes with all the other stuff and pass it through until it gets to a final mux
        This final mux would be after the current mux that takes regfile_wdata_sel as its input
        the selector for this would be an output from this module that tells it whether this module output
        a capability or an integer. This also means that this module also needs to have an enable selector
        since if not then it could accidentally hijack the last mux and write garbage to the register
        Again there are two ways of doing this:
          this module could have its output muxed in the EX block, which involves passing a signal from
            the decoder to the ex block saying whether this should be muxed in or not
          alternatively, this could have its output muxed in the mux that is currently controlled by regfile_wdata_sel
            For this i would have to add an extra value to the selector enum with cheri in it, and this module
            would have to pass its output all the way to the mux in the id stage. This module would still need to output
            whether its output was a capability or not. At the end we then choose just before we write to the register
            file whether we pass it through a nullwithaddr. we do if it came from the ex/lsu/csr blocks or if it
            came through the cheri block and the cheri block output a non-capability

*/

// TODO ask: there are various checks that compare otype and the base or top of capabilities
//        Are these going to cause issues for us?
//        they'll end up getting truncated

// TODO check all the writes to returnvalue are the correct size and correctly sign-extended

module ibex_cheri_alu (
  input ibex_defines::cheri_base_opcode_e             base_opcode_i,
  input ibex_defines::cheri_threeop_funct7_e          threeop_opcode_i,
  input ibex_defines::cheri_s_a_d_funct5_e  sad_opcode_i,
  input ibex_defines::cheri_ccall_e ccall_type_i,

  input logic [`CAP_SIZE-1:0] operand_a_i,
  input logic [`CAP_SIZE-1:0] operand_b_i,

  output logic [`INTEGER_SIZE-1:0] alu_operand_a_o,
  output logic [`INTEGER_SIZE-1:0] alu_operand_b_o,
  output ibex_defines::alu_op_e alu_operator_o,

  input logic [32:0] alu_result_i,

  output logic [`CAP_SIZE-1:0] returnvalue_o,
  output logic wroteCapability,

  output logic [`EXCEPTION_SIZE-1:0] exceptions_a_o,
  output logic [`EXCEPTION_SIZE-1:0] exceptions_b_o

);
  import ibex_defines::*;

  // there are 22 exceptions currently defined in the CHERI-RISCV spec
  // TODO see if there are any unused exceptions (there are some that are MIPS-only)
  logic [`EXCEPTION_SIZE-1:0] exceptions_a;
  logic [`EXCEPTION_SIZE-1:0] exceptions_b;


// function input and output declarations
// these are inputs and outputs for modules that were generated from bluespec code
// see https://github.com/CTSRD-CHERI/cheri-cap-lib for the bluespec code
// This is being used because the spec for cheri capability compression is still being worked on
// so it is possible the internals of the functions might change
// naming: O_FFF...FFF_D
// where O is the operand being worked on (operand a or b)
//       F is the function being used
//       D is the direction of the connection - _i means it is an input to the function
//                                              _o means it is an output from the function

logic [`INTEGER_SIZE-1:0] a_setBounds_i;
logic [`CAP_SIZE:0] a_setBounds_o;

logic [`INTEGER_SIZE-1:0] a_getAddr_o;

logic [`INTEGER_SIZE-1:0] b_getAddr_o;

logic [`INTEGER_SIZE:0] a_getTop_o;

logic [`INTEGER_SIZE:0] b_getTop_o;

logic [`CAP_SIZE-1:0] a_setType_cap_i;
logic [`OTYPE_SIZE-1:0] a_setType_i;
logic [`CAP_SIZE:0] a_setType_o;

logic [`OTYPE_SIZE-1:0] b_setType_i;
logic [`CAP_SIZE:0] b_setType_o;

logic [`PERMS_SIZE-1:0] a_getPerms_o;

logic [`PERMS_SIZE-1:0] b_getPerms_o;

logic [`PERMS_SIZE-1:0] a_setPerms_i;
logic [`CAP_SIZE-1:0] a_setPerms_o;

logic [`PERMS_SIZE-1:0] b_setPerms_i;
logic [`CAP_SIZE-1:0] b_setPerms_o;

logic a_setFlags_i;
logic [`CAP_SIZE-1:0] a_setFlags_o;

logic [`INTEGER_SIZE-1:0] a_setOffset_i;
logic [`CAP_SIZE:0] a_setOffset_o;

logic [`INTEGER_SIZE-1:0] a_getBase_o;

logic [`INTEGER_SIZE-1:0] b_getBase_o;

logic [`INTEGER_SIZE-1:0] a_getOffset_o;

logic [`INTEGER_SIZE-1:0] b_getOffset_o;

logic a_isValidCap_o;

logic b_isValidCap_o;

logic a_isSealed_o;

logic b_isSealed_o;

logic [`OTYPE_SIZE-1:0] a_getType_o;

logic [`OTYPE_SIZE-1:0] b_getType_o;

logic [`INTEGER_SIZE:0] a_getLength_o;

logic a_getFlags_o;

logic a_setValidCap_i;
logic [`CAP_SIZE-1:0] a_setValidCap_o;

logic b_setValidCap_i;
logic [`CAP_SIZE-1:0] b_setValidCap_o;

logic [`INTEGER_SIZE-1:0] a_setAddr_i;
logic [`CAP_SIZE:0] a_setAddr_o;

logic [`INTEGER_SIZE-1:0] b_setAddr_i;
logic [`CAP_SIZE:0] b_setAddr_o;



  // operations
  always_comb begin
    exceptions_a_o = '0;
    exceptions_b_o = '0;

    alu_operand_a_o = '0;
    alu_operand_b_o = '0;
    alu_operator_o = ALU_ADD;
    returnvalue_o = '0;
    wroteCapability = '0;

    a_setBounds_i = '0;
    a_setType_cap_i = '0;
    a_setType_i = '0;
    b_setType_i = '0;
    a_setPerms_i = '0;
    b_setPerms_i = '0;
    a_setFlags_i = '0;
    a_setOffset_i = '0;
    a_setValidCap_i = '0;
    b_setValidCap_i = '0;
    a_setAddr_i = '0;
    b_setAddr_i = '0;

    case (base_opcode_i)
      THREE_OP: begin
        case (threeop_opcode_i)
          C_SPECIAL_RW: begin
            // operand b is the register id
            // operand a is the data that is (maybe) going to be written to the register
            // this operation is implemented in other places since there's nothing the ALU can do
            // for it
            returnvalue_o = operand_a_i;
            //$display("cspecialrw output: %h", returnvalue_o);
            wroteCapability = 1'b1;
          end

          C_SET_BOUNDS: begin
            a_setBounds_i = operand_b_i;
            returnvalue_o = a_setBounds_o[`CAP_SIZE-1:0];
            wroteCapability = 1'b1;

            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = operand_b_i;
            alu_operator_o = ALU_ADD;

            exceptions_a_o =( exceptions_a[TAG_VIOLATION]    )  << TAG_VIOLATION
                           |( exceptions_a[SEAL_VIOLATION]   )  << SEAL_VIOLATION
                           |( exceptions_a[LENGTH_VIOLATION] )  << LENGTH_VIOLATION
                           |( alu_result_i > a_getTop_o      )  << LENGTH_VIOLATION;
            //$display("csetbounds output: %h   exceptions: %h", returnvalue_o, exceptions_a_o);
          end

          C_SET_BOUNDS_EXACT: begin
            a_setBounds_i = operand_b_i;
            returnvalue_o = a_setBounds_o[`CAP_SIZE-1:0];
            wroteCapability = 1'b1;

            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = operand_b_i;
            alu_operator_o = ALU_ADD;


            exceptions_a_o =( exceptions_a[TAG_VIOLATION]    )  << TAG_VIOLATION
                           |( exceptions_a[SEAL_VIOLATION]   )  << SEAL_VIOLATION
                           |( exceptions_a[LENGTH_VIOLATION] )  << LENGTH_VIOLATION
                           |( alu_result_i > a_getTop_o      )  << LENGTH_VIOLATION
                           |( !a_setBounds_o[`CAP_SIZE]      )  << INEXACT_BOUNDS_VIOLATION;
            //$display("csetboundse output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_SEAL: begin
            a_setType_cap_i = operand_a_i;
            a_setType_i = b_getAddr_o;
            returnvalue_o = a_setType_o;
            wroteCapability = 1'b1;

            exceptions_a_o =( exceptions_a[TAG_VIOLATION]  ) << TAG_VIOLATION
                           |( exceptions_a[SEAL_VIOLATION] ) << SEAL_VIOLATION
                           |( !a_setType_o[`CAP_SIZE]      ) << INEXACT_BOUNDS_VIOLATION;

            exceptions_b_o =( exceptions_b[TAG_VIOLATION]          ) << TAG_VIOLATION
                           |( exceptions_b[SEAL_VIOLATION]         ) << SEAL_VIOLATION
                           |( exceptions_b[LENGTH_VIOLATION]       ) << LENGTH_VIOLATION
                           |( b_getAddr_o >= b_getTop_o            ) << LENGTH_VIOLATION
                           // TODO use validAsType when it gets fixed
                           |( b_getAddr_o > `MAX_OTYPE             ) << LENGTH_VIOLATION //-1 means unsealed
                           |( exceptions_b[PERMIT_SEAL_VIOLATION]  ) << PERMIT_SEAL_VIOLATION;
            //$display("cseal output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_UNSEAL: begin
            a_setPerms_i = a_getPerms_o;
            a_setPerms_i[`PERMIT_GLOBAL_INDEX] = a_getPerms_o[`PERMIT_GLOBAL_INDEX] & b_getPerms_o[`PERMIT_GLOBAL_INDEX];
            a_setType_cap_i = a_setPerms_o;
            a_setType_i = {`OTYPE_SIZE{1'b1}};
            returnvalue_o = a_setType_o;
            wroteCapability = 1'b1;

            exceptions_a_o =( exceptions_a[TAG_VIOLATION] ) << TAG_VIOLATION
                           |( !a_isSealed_o               ) << SEAL_VIOLATION;

            exceptions_b_o =( exceptions_b[TAG_VIOLATION]           ) << TAG_VIOLATION
                           |( b_isSealed_o                          ) << SEAL_VIOLATION
                           |( b_getAddr_o != a_getType_o            ) << TYPE_VIOLATION
                           |( exceptions_b[PERMIT_UNSEAL_VIOLATION] ) << PERMIT_UNSEAL_VIOLATION
                           |( b_getAddr_o >= b_getTop_o             ) << LENGTH_VIOLATION;
            //$display("cunseal output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_AND_PERM: begin
            a_setPerms_i = a_getPerms_o & operand_b_i[`PERMS_SIZE-1:0];
            returnvalue_o = a_setPerms_o;
            wroteCapability = 1'b1;

            exceptions_a_o =( exceptions_a[TAG_VIOLATION]  ) << TAG_VIOLATION
                           |( exceptions_a[SEAL_VIOLATION] ) << SEAL_VIOLATION;

            //$display("candperm output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_SET_FLAGS: begin
            a_setFlags_i = operand_b_i[`PERMS_SIZE-1:0];
            returnvalue_o = a_setFlags_o;
            wroteCapability = 1'b1;

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
            //$display("csetflags output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_SET_OFFSET: begin
            a_setOffset_i = operand_b_i;

            alu_operand_a_o = a_getBase_o;
            alu_operand_b_o = operand_b_i;
            alu_operator_o = ALU_ADD;

            returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o[`CAP_SIZE-1:0] :
                                                       alu_result_i;
            wroteCapability = a_setOffset_o[`CAP_SIZE];

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
            //$display("csetoffset output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_SET_ADDR: begin
            a_setAddr_i = operand_b_i;
            returnvalue_o = a_setAddr_o[`CAP_SIZE] ? a_setAddr_o[`CAP_SIZE-1:0] : operand_b_i;

            wroteCapability = a_setAddr_o[`CAP_SIZE];

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
            //$display("csetaddr output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_INC_OFFSET: begin
            // TODO remove adders here?
            a_setOffset_i = a_getOffset_o + operand_b_i;
            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = operand_b_i;
            alu_operator_o = ALU_ADD;

            returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o[`CAP_SIZE-1:0] :
                                                       alu_result_i;
            wroteCapability = a_setOffset_o[`CAP_SIZE];

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
            //$display("cincoffset output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_TO_PTR: begin
            returnvalue_o = a_isValidCap_o ? a_getAddr_o - b_getBase_o : `INTEGER_SIZE'b0;

            wroteCapability = 1'b0;

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;

            exceptions_b_o = exceptions_b[TAG_VIOLATION] << TAG_VIOLATION;
            //$display("ctoptr output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_FROM_PTR: begin
            a_setOffset_i = operand_b_i;

            alu_operand_a_o = a_getBase_o;
            alu_operand_b_o = operand_b_i;
            alu_operator_o = ALU_ADD;

            returnvalue_o = operand_b_i == '0        ? operand_b_i :
                            a_setOffset_o[`CAP_SIZE] ? a_setOffset_o[`CAP_SIZE-1:0] :
                                                       alu_result_i;

            wroteCapability = operand_b_i == '0        ? 1'b0 :
                              a_setOffset_o[`CAP_SIZE] ? 1'b1 :
                                                         1'b0;

            exceptions_a_o =( operand_b_i != '0 && exceptions_a[TAG_VIOLATION]  ) << TAG_VIOLATION
                           |( operand_b_i != '0 && exceptions_a[SEAL_VIOLATION] ) << SEAL_VIOLATION;
            //$display("cfromptr output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_SUB: begin
            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = b_getAddr_o;
            alu_operator_o = ALU_SUB;

            returnvalue_o = a_getAddr_o - b_getAddr_o;
            wroteCapability = 1'b0;
            //$display("csub output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_BUILD_CAP: begin
            b_setType_i = a_getType_o;
            returnvalue_o = b_setType_o | {1'b1, {`CAP_SIZE-1{1'b0}}};
            wroteCapability = 1'b1;

            exceptions_a_o =( exceptions_a[TAG_VIOLATION]                   ) << TAG_VIOLATION
                           |( exceptions_a[SEAL_VIOLATION]                  ) << SEAL_VIOLATION
                           |( b_getBase_o < a_getBase_o                     ) << LENGTH_VIOLATION
                           |( b_getTop_o > a_getTop_o                       ) << LENGTH_VIOLATION
                           |( (a_getPerms_o & b_getPerms_o) != b_getPerms_o ) << SOFTWARE_DEFINED_VIOLATION;

            exceptions_b_o = (b_getBase_o > b_getTop_o) << LENGTH_VIOLATION;
            //$display("cbuildcap output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_COPY_TYPE: begin
            /*
              in implementing this instruction, i've followed this code rather than the one in the sail spec
              this should be functionally equivalent, but i've included it just in case i've made a blunder

              let cb_val = readCapReg(cb);
              let ct_val = readCapReg(ct);
              let cb_base = getCapBase(cb_val);
              let cb_top = getCapTop(cb_val);
              let ct_otype = unsigned(ct_val.otype);
              if not (cb_val.tag) then {
                handle_cheri_reg_exception(CapEx_TagViolation, cb);
                RETIRE_FAIL
              } else if cb_val.sealed then {
                handle_cheri_reg_exception(CapEx_SealViolation, cb);
                RETIRE_FAIL
              } else if ct_val.sealed && ct_otype < cb_base then {
                handle_cheri_reg_exception(CapEx_LengthViolation, cb);
                RETIRE_FAIL
              } else if ct_val.sealed && ct_otype >= cb_top then {
                handle_cheri_reg_exception(CapEx_LengthViolation, cb);
                RETIRE_FAIL
              } else {
                let (success, cap) = setCapOffset(cb_val, to_bits(64, ct_otype - cb_base));
                assert(success, "CopyType: offset is in bounds so should be representable");
                writeCapReg(cd, ct_val.sealed ? cap : int_to_cap(0xffffffffffffffff));
                RETIRE_SUCCESS
              }
            */

            a_setOffset_i = b_getType_o - a_getBase_o;
            returnvalue_o = b_isSealed_o ? a_setOffset_o : {`INTEGER_SIZE{1'b1}};
            wroteCapability = b_isSealed_o;

            exceptions_a_o =( exceptions_a[TAG_VIOLATION]               ) << TAG_VIOLATION
                           |( exceptions_a[SEAL_VIOLATION]              ) << SEAL_VIOLATION
                           |( b_isSealed_o && b_getType_o < a_getBase_o ) << LENGTH_VIOLATION
                           |( b_isSealed_o && b_getType_o >= a_getTop_o ) << LENGTH_VIOLATION;
            //$display("ccopytype output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          // TODO C_C_SEAL is working (probably, haven't found any issues yet) but needs to be rewritten below to look decent
          C_C_SEAL: begin
            a_setType_cap_i = operand_a_i;
            a_setType_i = b_getAddr_o;
            returnvalue_o = (!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}}) ? operand_a_i : a_setType_o;
            wroteCapability = 1'b1;


            exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            |((exceptions_a[SEAL_VIOLATION] && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}}))
                               << SEAL_VIOLATION);

            exceptions_b_o =( exceptions_b[SEAL_VIOLATION]        && b_isValidCap_o && b_getAddr_o != {`INTEGER_SIZE{1'b1}} ) << SEAL_VIOLATION
                           |( exceptions_b[PERMIT_SEAL_VIOLATION] && b_isValidCap_o && b_getAddr_o != {`INTEGER_SIZE{1'b1}} ) << PERMIT_SEAL_VIOLATION
                           |( exceptions_b[LENGTH_VIOLATION]      && b_isValidCap_o && b_getAddr_o != {`INTEGER_SIZE{1'b1}} ) << LENGTH_VIOLATION
                           // TODO use validAsType when it gets fixed
                           |( b_getAddr_o >= b_getTop_o           && b_isValidCap_o && b_getAddr_o != {`INTEGER_SIZE{1'b1}} ) << LENGTH_VIOLATION
                           |( b_getAddr_o > `MAX_OTYPE            && b_isValidCap_o && b_getAddr_o != {`INTEGER_SIZE{1'b1}} ) << LENGTH_VIOLATION;
            //$display("ccseal output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          C_TEST_SUBSET: begin
            returnvalue_o = a_isValidCap_o != b_isValidCap_o              ? 1'b0 :
                            b_getBase_o < a_getBase_o                     ? 1'b0 :
                            b_getTop_o > a_getTop_o                       ? 1'b0 :
                            (b_getPerms_o & a_getPerms_o) == b_getPerms_o ? 1'b0 :
                                                                            1'b1;
            wroteCapability = 1'b0;
            //$display("ctestsubset output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
          end

          TWO_SOURCE: begin
            // when trying to read this using the Sail definitions, cs is my operand_a and cb is my operand_b
            unique case (ccall_type_i)
              CCALL_CYCLE1: begin
                a_setAddr_i = {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0};

                exceptions_a_o =( exceptions_a[TAG_VIOLATION]                                            ) << TAG_VIOLATION
                               |( !exceptions_a[SEAL_VIOLATION]                                          ) << SEAL_VIOLATION // we want it to be sealed
                               |( a_getType_o != b_getType_o                                             ) << TYPE_VIOLATION
                               |( exceptions_a[PERMIT_CCALL_VIOLATION]                                   ) << PERMIT_CCALL_VIOLATION
                               |( exceptions_a[PERMIT_EXECUTE_VIOLATION]                                 ) << PERMIT_EXECUTE_VIOLATION
                               |( {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0} < a_getBase_o                   ) << LENGTH_VIOLATION
                               |( {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0} + `MIN_INSTR_BYTES > a_getTop_o ) << LENGTH_VIOLATION;

                exceptions_b_o =( exceptions_b[TAG_VIOLATION]             ) << TAG_VIOLATION
                               |( !exceptions_b[SEAL_VIOLATION]           ) << SEAL_VIOLATION
                               |( !exceptions_b[PERMIT_EXECUTE_VIOLATION] ) << PERMIT_EXECUTE_VIOLATION
                               |( exceptions_b[PERMIT_CCALL_VIOLATION]    ) << PERMIT_CCALL_VIOLATION;

                a_setType_cap_i = a_setAddr_o;
                a_setType_i = {`OTYPE_SIZE{1'b1}};
                wroteCapability = 1'b1;
                returnvalue_o = a_setType_o;
              end

              CCALL_CYCLE2: begin
                a_setAddr_i = {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0};

                exceptions_a_o =( exceptions_a[TAG_VIOLATION]                                            ) << TAG_VIOLATION
                               |( !exceptions_a[SEAL_VIOLATION]                                          ) << SEAL_VIOLATION // we want it to be sealed
                               |( a_getType_o != b_getType_o                                             ) << TYPE_VIOLATION
                               |( exceptions_a[PERMIT_CCALL_VIOLATION]                                   ) << PERMIT_CCALL_VIOLATION
                               |( exceptions_a[PERMIT_EXECUTE_VIOLATION]                                 ) << PERMIT_EXECUTE_VIOLATION
                               |( {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0} < a_getBase_o                   ) << LENGTH_VIOLATION
                               |( {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0} + `MIN_INSTR_BYTES > a_getTop_o ) << LENGTH_VIOLATION;

                exceptions_b_o =( exceptions_b[TAG_VIOLATION]                ) << TAG_VIOLATION
                               |( (!exceptions_b[SEAL_VIOLATION]             ) << SEAL_VIOLATION)
                               |( ((!exceptions_b[PERMIT_EXECUTE_VIOLATION]) ) << PERMIT_EXECUTE_VIOLATION)
                               |( exceptions_b[PERMIT_CCALL_VIOLATION]       ) << PERMIT_CCALL_VIOLATION;

                b_setType_i = {`OTYPE_SIZE{1'b1}};
                wroteCapability = 1'b1;
                returnvalue_o = b_setType_o;
              end
            endcase
          end

          SOURCE_AND_DEST: begin
            case(sad_opcode_i)
              C_GET_PERM: begin
                returnvalue_o = {{`INTEGER_SIZE-`PERMS_SIZE{1'b0}}, a_getPerms_o};
                wroteCapability = 1'b0;
            //$display("cgetperm output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_TYPE: begin
                returnvalue_o = a_isSealed_o ? {{`INTEGER_SIZE-`OTYPE_SIZE{1'b0}}, a_getType_o} : {`INTEGER_SIZE{1'b1}};
                wroteCapability = 1'b0;
            //$display("cgettype output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_BASE: begin
                returnvalue_o = a_getBase_o;
                wroteCapability = 1'b0;
            //$display("cgetbase output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_LEN: begin
                returnvalue_o = a_getLength_o[`LENGTH_SIZE-1] ? {`INTEGER_SIZE{1'b1}} : a_getLength_o[`INTEGER_SIZE-1:0];
                wroteCapability = 1'b0;
            //$display("cgetlen output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_TAG: begin
                returnvalue_o = {{`INTEGER_SIZE-1{1'b0}}, a_isValidCap_o};
                wroteCapability = 1'b0;
            //$display("cgettag output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_SEALED: begin
                returnvalue_o = {{`INTEGER_SIZE-`OTYPE_SIZE{1'b0}}, a_isSealed_o};
                wroteCapability = 1'b0;
            //$display("cgetsealed output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_OFFSET: begin
                returnvalue_o = {{`INTEGER_SIZE-`OFFSET_SIZE{1'b0}}, a_getOffset_o};
                wroteCapability = 1'b0;
            //$display("cgetoffset output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_GET_FLAGS: begin
                returnvalue_o = {{`INTEGER_SIZE-`FLAG_SIZE{1'b0}}, a_getFlags_o};
                wroteCapability = 1'b0;
            //$display("cgetflags output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_MOVE: begin
                returnvalue_o = operand_a_i;
                wroteCapability = 1'b1;
            //$display("cmove output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_CLEAR_TAG: begin
                a_setValidCap_i = 1'b0;
                returnvalue_o = a_setValidCap_o;
                wroteCapability = 1'b1;
            //$display("ccleartag output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              C_JALR: begin
                // current implementation of JAL and JALR:
                // ibex takes 2 cycles to do a normal JAL and JALR, so this one can also take 2 cycles
                // in the first cycle, ibex calculates the jump target and sends it to the IF stage
                // in the second cycle, ibex calculates the old PC + 4 and stores that in the destination
                // register

                // potential implementation of CJALR:
                // we call this instruction here for the first cycle. we do all the exception checking
                // here, and calculate the next PCC from the input register
                // in the second cycle, we just do an incoffsetimm with a = old pcc and b = 4
                // issue is this isn't a very clean way of doing this - we need to fake incoffsetimm instruction
                // in the decoder. However, ibex already does it this way.

                a_setAddr_i = {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0};
                returnvalue_o = a_setAddr_o;
                wroteCapability = 1'b1;

                alu_operand_a_o = {a_getAddr_o[`INTEGER_SIZE-1:1], 1'b0};
                alu_operand_b_o = `MIN_INSTR_BYTES;
                alu_operator_o = ALU_ADD;

                exceptions_a_o =( exceptions_a[TAG_VIOLATION]            ) << TAG_VIOLATION
                               |( exceptions_a[SEAL_VIOLATION]           ) << SEAL_VIOLATION
                               |( exceptions_a[PERMIT_EXECUTE_VIOLATION] ) << PERMIT_EXECUTE_VIOLATION
                               |( exceptions_a[LENGTH_VIOLATION]         ) << LENGTH_VIOLATION
                               |( ((alu_result_i > a_getTop_o)           ) << LENGTH_VIOLATION);
                                // we don't care about trying to throw the last exception since we do support
                                // compressed instructions

            //$display("cjalr output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              // TODO implement elsewhere
              CLEAR: begin
              end

              C_GET_ADDR: begin
                returnvalue_o = a_getAddr_o;
                wroteCapability = 1'b0;
            ////$display("cgetaddr output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
              end

              default: begin
                ////$display("something went wrong in the ibex_alu");
              end
            endcase
          end


              default: begin
                //$display("something went wrong in the ibex_alu");
              end
        endcase
      end

      C_INC_OFFSET_IMM: begin
        // TODO remove adders?
        a_setOffset_i = a_getOffset_o + operand_b_i;
        //returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o : a_getAddr_o + (operand_b_i[`IMM_SIZE-1] ? {{`INTEGER_SIZE-`IMM_SIZE{1'b1}}, operand_b_i} : operand_b_i);
        returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o : a_getAddr_o + operand_b_i;
        wroteCapability = a_setOffset_o[`CAP_SIZE];

        exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
            //$display("cincoffsetimm output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
      end

      C_SET_BOUNDS_IMM: begin
        // need to truncate input since we want it to be unsigned
        a_setBounds_i = operand_b_i[`IMM_SIZE-1:0];
        returnvalue_o = a_setBounds_o[`CAP_SIZE-1:0];
        wroteCapability = 1'b1;

        alu_operand_a_o = a_getAddr_o;
        alu_operand_b_o = {{`INTEGER_SIZE-`IMM_SIZE{1'b0}}, operand_b_i[`IMM_SIZE-1:0]};
        alu_operator_o = ALU_ADD;

        exceptions_a_o =( exceptions_a[TAG_VIOLATION]    ) << TAG_VIOLATION
                       |( exceptions_a[SEAL_VIOLATION]   ) << SEAL_VIOLATION
                       |( exceptions_a[LENGTH_VIOLATION] ) << LENGTH_VIOLATION
                       |( alu_result_i > a_getTop_o      ) << LENGTH_VIOLATION;
            //$display("csetboundsimm output: %h   exceptions: %h   exceptions_b: %h", returnvalue_o, exceptions_a_o, exceptions_b_o);
      end

      default: begin
        //$display("something went wrong in the ibex_alu");
      end

    endcase
  end


// TODO rename/rearrange/refactor these

module_wrap64_setBounds module_wrap64_setBounds_a (
      .wrap64_setBounds_cap     (operand_a_i),
      .wrap64_setBounds_length  (a_setBounds_i),
      .wrap64_setBounds         (a_setBounds_o));

module_wrap64_getAddr module_getAddr_a (
      .wrap64_getAddr_cap (operand_a_i),
      .wrap64_getAddr     (a_getAddr_o));

module_wrap64_getAddr module_getAddr_b (
      .wrap64_getAddr_cap (operand_b_i),
      .wrap64_getAddr     (b_getAddr_o));

module_wrap64_getTop module_wrap64_getTop_a (
      .wrap64_getTop_cap  (operand_a_i),
      .wrap64_getTop      (a_getTop_o));

module_wrap64_getTop module_wrap64_getTop_b (
      .wrap64_getTop_cap  (operand_b_i),
      .wrap64_getTop      (b_getTop_o));

module_wrap64_setType module_wrap64_setType_a (
      .wrap64_setType_cap   (a_setType_cap_i),
      .wrap64_setType_otype (a_setType_i),
      .wrap64_setType       (a_setType_o));

module_wrap64_setType module_wrap64_setType_b (
      .wrap64_setType_cap   (operand_b_i),
      .wrap64_setType_otype (b_setType_i),
      .wrap64_setType       (b_setType_o));

module_wrap64_getPerms module_wrap64_getPerms_a (
      .wrap64_getPerms_cap  (operand_a_i),
      .wrap64_getPerms      (a_getPerms_o));

module_wrap64_getPerms module_wrap64_getPerms_b (
      .wrap64_getPerms_cap  (operand_b_i),
      .wrap64_getPerms      (b_getPerms_o));


module_wrap64_setPerms module_wrap64_setPerms_a (
      .wrap64_setPerms_cap    (operand_a_i),
      .wrap64_setPerms_perms  (a_setPerms_i),
      .wrap64_setPerms        (a_setPerms_o));

module_wrap64_setPerms module_wrap64_setPerms_b (
      .wrap64_setPerms_cap    (operand_b_i),
      .wrap64_setPerms_perms  (b_setPerms_i),
      .wrap64_setPerms        (b_setPerms_o));

module_wrap64_setFlags module_wrap64_setFlags_a (
      .wrap64_setFlags_cap    (operand_a_i),
      .wrap64_setFlags_flags  (a_setFlags_i),
      .wrap64_setFlags        (a_setFlags_o));

module_wrap64_setOffset module_wrap64_setOffset_a (
      .wrap64_setOffset_cap   (operand_a_i),
      .wrap64_setOffset_offset(a_setOffset_i),
      .wrap64_setOffset       (a_setOffset_o));

module_wrap64_getBase module_getBase_a (
      .wrap64_getBase_cap     (operand_a_i),
      .wrap64_getBase         (a_getBase_o));

module_wrap64_getBase module_getBase_b (
      .wrap64_getBase_cap     (operand_b_i),
      .wrap64_getBase         (b_getBase_o));

module_wrap64_getOffset module_getOffset_a (
      .wrap64_getOffset_cap   (operand_a_i),
      .wrap64_getOffset       (a_getOffset_o));

module_wrap64_getOffset module_getOffset_b (
      .wrap64_getOffset_cap   (operand_b_i),
      .wrap64_getOffset       (b_getOffset_o));

module_wrap64_isValidCap module_wrap64_isValidCap_a (
      .wrap64_isValidCap_cap  (operand_a_i),
      .wrap64_isValidCap      (a_isValidCap_o));

module_wrap64_isValidCap module_wrap64_isValidCap_b (
      .wrap64_isValidCap_cap  (operand_b_i),
      .wrap64_isValidCap      (b_isValidCap_o));

module_wrap64_isSealed module_wrap64_isSealed_a (
      .wrap64_isSealed_cap    (operand_a_i),
      .wrap64_isSealed        (a_isSealed_o));

module_wrap64_isSealed module_wrap64_isSealed_b (
      .wrap64_isSealed_cap    (operand_b_i),
      .wrap64_isSealed        (b_isSealed_o));

module_wrap64_getType module_wrap64_getType_a (
      .wrap64_getType_cap     (operand_a_i),
      .wrap64_getType         (a_getType_o));

module_wrap64_getType module_wrap64_getType_b (
      .wrap64_getType_cap     (operand_b_i),
      .wrap64_getType         (b_getType_o));

module_wrap64_getLength module_getLength_a (
      .wrap64_getLength_cap   (operand_a_i),
      .wrap64_getLength       (a_getLength_o));

module_wrap64_getFlags module_getFlags_a (
      .wrap64_getFlags_cap    (operand_a_i),
      .wrap64_getFlags        (a_getFlags_o));

module_wrap64_setValidCap module_wrap64_setValidCap_a (
      .wrap64_setValidCap_cap   (operand_a_i),
      .wrap64_setValidCap_valid (a_setValidCap_i),
      .wrap64_setValidCap       (a_setValidCap_o));

module_wrap64_setValidCap module_wrap64_setValidCap_b (
      .wrap64_setValidCap_cap   (operand_b_i),
      .wrap64_setValidCap_valid (b_setValidCap_i),
      .wrap64_setValidCap       (b_setValidCap_o));

module_wrap64_setAddr module_wrap64_setAddr_a (
      .wrap64_setAddr_cap       (operand_a_i),
	  .wrap64_setAddr_addr      (a_setAddr_i),
	  .wrap64_setAddr           (a_setAddr_o));

module_wrap64_setAddr module_wrap64_setAddr_b (
      .wrap64_setAddr_cap   (operand_b_i),
 	  .wrap64_setAddr_addr  (b_setAddr_i),
 	  .wrap64_setAddr       (b_setAddr_o));




  // TODO
  // strictly speaking, some of the exceptions that are being set after isSealed and
  // isValidCap would need to be &&'d with the negative of the ones above them
  // (ie a_isValidCap_o && !a_isSealed_o && a_CURSOR_o < a_isSealed_o)
  // this may not actually be needed because exceptions have priorities

  // check for common violations
  always_comb begin
    exceptions_a = `EXCEPTION_SIZE'b0;
    exceptions_b = `EXCEPTION_SIZE'b0;

    if (!a_isValidCap_o)
      exceptions_a[TAG_VIOLATION] = 1'b1;

    if (!b_isValidCap_o)
      exceptions_b[TAG_VIOLATION] = 1'b1;

    if (a_isValidCap_o && a_isSealed_o)
      exceptions_a[SEAL_VIOLATION] = 1'b1;

    if (b_isValidCap_o && b_isSealed_o)
      exceptions_b[SEAL_VIOLATION] = 1'b1;

    if (a_getAddr_o < a_getBase_o)
      exceptions_a[LENGTH_VIOLATION] = 1'b1;

    if (b_getAddr_o < b_getBase_o)
      exceptions_b[LENGTH_VIOLATION] = 1'b1;

    if (a_getType_o != b_getType_o)
      exceptions_a[TYPE_VIOLATION] = 1'b1;

    if (!b_getPerms_o[`PERMIT_UNSEAL_INDEX])
      exceptions_b[PERMIT_UNSEAL_VIOLATION] = 1'b1;

    if (!b_getPerms_o[`PERMIT_SEAL_INDEX])
      exceptions_b[PERMIT_SEAL_VIOLATION] = 1'b1;

    if (!a_getPerms_o[`PERMIT_EXECUTE_INDEX])
      exceptions_a[PERMIT_EXECUTE_VIOLATION] = 1'b1;

    if (!b_getPerms_o[`PERMIT_EXECUTE_INDEX])
      exceptions_b[PERMIT_EXECUTE_VIOLATION] = 1'b1;

    if (!a_getPerms_o[`PERMIT_CCALL_INDEX])
      exceptions_a[PERMIT_CCALL_VIOLATION] = 1'b1;

    if (!b_getPerms_o[`PERMIT_CCALL_INDEX])
      exceptions_b[PERMIT_CCALL_VIOLATION] = 1'b1;

  end
endmodule
