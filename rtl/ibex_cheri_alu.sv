
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
`define PERMIT_EXECUTE_INDEX 10
`define MIN_INSTR_BYTES 2


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
  input ibex_defines::cheri_store_funct5_e            store_opcode_i,
  input ibex_defines::cheri_load_funct5_e             load_opcode_i,
  input ibex_defines::cheri_s_a_d_funct5_e  sad_opcode_i,

  input logic [`CAP_SIZE-1:0] operand_a_i,
  input logic [`CAP_SIZE-1:0] operand_b_i,

  output logic [`INTEGER_SIZE-1:0] alu_operand_a_o,
  output logic [`INTEGER_SIZE-1:0] alu_operand_b_o,
  input logic [31:0] alu_result_i,

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

  always_comb begin
    exceptions_a_o = '0;
    exceptions_b_o = '0;
    case (base_opcode_i)
      THREE_OP: begin
        case (threeop_opcode_i)
          // TODO implement later
          C_SPECIAL_RW: begin

          end

          C_SET_BOUNDS: begin
            a_setBounds_i = operand_b_i;
            returnvalue_o = a_setBounds_o[`CAP_SIZE-1:0];
            wroteCapability = 1'b1;

            alu_operand_a_o = a_getAddr_o;
            alu_operand_b_o = operand_b_i;

            exceptions_a_o =   exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            |  exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                            |  exceptions_a[LENGTH_VIOLATION] << LENGTH_VIOLATION
                            |  ((alu_result_i > a_getTop_o) << LENGTH_VIOLATION);
          end

          C_SET_BOUNDS_EXACT: begin
            a_setBounds_i = operand_b_i;
            returnvalue_o = a_setBounds_o[`CAP_SIZE-1:0];
            wroteCapability = 1'b1;
            
            
            exceptions_a_o =    (  exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                                 | exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                                 | exceptions_a[LENGTH_VIOLATION] << LENGTH_VIOLATION
                                )
                              | ((a_getAddr_o + operand_b_i > a_getTop_o) << LENGTH_VIOLATION)
                              | ((!a_setBounds_o[`CAP_SIZE] << INEXACT_BOUNDS_VIOLATION));
          end

          C_SEAL: begin
            a_setType_i = b_getAddr_o;
            returnvalue_o = a_setType_o;
            wroteCapability = 1'b1;

            exceptions_a_o =    exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                              | exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                              | ((!a_setType_o[`CAP_SIZE] << INEXACT_BOUNDS_VIOLATION));
            
            exceptions_b_o =  ( exceptions_b[TAG_VIOLATION] << TAG_VIOLATION
                              | exceptions_b[SEAL_VIOLATION] << SEAL_VIOLATION
                              | exceptions_b[LENGTH_VIOLATION] << LENGTH_VIOLATION)
                              | ((b_getAddr_o > b_getTop_o) << LENGTH_VIOLATION)
                              // capabilities with type -1 are unsealed
                              | ((b_getAddr_o > {`OTYPE_SIZE{1'b1}}) << LENGTH_VIOLATION)
                              | exceptions_b[PERMIT_SEAL_VIOLATION] << PERMIT_SEAL_VIOLATION;
          end

          C_UNSEAL: begin
            a_setType_i = {`OTYPE_SIZE{1'b1}};
            returnvalue_o = a_setType_o;
            wroteCapability = 1'b1;

            exceptions_a_o =  exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            | ((!a_isSealed_o) << SEAL_VIOLATION);

            exceptions_b_o =  exceptions_b[TAG_VIOLATION] << TAG_VIOLATION
                            | b_isSealed_o << SEAL_VIOLATION
                            // TODO check this (does it need to be truncated?)
                            | ((b_getAddr_o != a_getType_o) << TYPE_VIOLATION)
                            | exceptions_b[PERMIT_UNSEAL_VIOLATION] << PERMIT_UNSEAL_VIOLATION
                            | ((b_getAddr_o >= b_getTop_o) << LENGTH_VIOLATION);
          end

          C_AND_PERM: begin
            a_setPerms_i = a_getPerms_o & operand_b_i[`PERMS_SIZE-1:0];
            returnvalue_o = a_setPerms_o;
            wroteCapability = 1'b1;

            exceptions_a_o = (exceptions_a & (   1'b1 << TAG_VIOLATION
                                               | 1'b1 << SEAL_VIOLATION));
          end

          C_SET_FLAGS: begin
            a_setFlags_i = operand_b_i[`PERMS_SIZE-1:0];
            returnvalue_o = a_setFlags_o;
            wroteCapability = 1'b1;

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
          end

          C_SET_OFFSET: begin
            a_setOffset_i = operand_b_i;
            returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o[`CAP_SIZE-1:0] :
                                                      a_getBase_o + operand_b_i;
            wroteCapability = a_setOffset_o[`CAP_SIZE];
            
            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
          end
          
          C_SET_ADDR: begin
            a_setAddr_i = operand_b_i;
            returnvalue_o = a_setAddr_o[`CAP_SIZE] ? a_setAddr_o[`CAP_SIZE-1:0] : operand_b_i;

            wroteCapability = a_setAddr_o[`CAP_SIZE];
            
            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
          end

          C_INC_OFFSET: begin
            a_setOffset_i = a_getOffset_o + operand_b_i;
            returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o[`CAP_SIZE-1:0] :
                                                      a_getAddr_o + operand_b_i;
            wroteCapability = a_setOffset_o[`CAP_SIZE];

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
          end

          C_TO_PTR: begin
            returnvalue_o = a_isValidCap_o ? a_getAddr_o - b_getBase_o :
                                             `INTEGER_SIZE'b0;
            wroteCapability = 1'b0;

            exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;

            exceptions_b_o = exceptions_b[TAG_VIOLATION] << TAG_VIOLATION;
          end

          C_FROM_PTR: begin
            // TODO rewrite this to remove the if statement
            if (operand_b_i == '0) begin
              // TODO minor optimisation: don't have a nullWithAddr in here and just mark it as not a cap?
              nullWithAddr_i = operand_b_i;
              returnvalue_o = nullWithAddr_o;
              wroteCapability = 1'b1;
            end else begin
              a_setOffset_i = operand_b_i;
              returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o[`CAP_SIZE-1:0] :
                                                        a_getBase_o + operand_b_i;
              wroteCapability = a_setOffset_o[`CAP_SIZE];
            end

            exceptions_a_o =  (operand_b_i != '0 && exceptions_a[TAG_VIOLATION]) << TAG_VIOLATION
                            | (operand_b_i != '0 && exceptions_a[SEAL_VIOLATION]) << SEAL_VIOLATION;
          end

          C_SUB: begin
            returnvalue_o = a_getAddr_o - b_getAddr_o;
            wroteCapability = 0'b0;
          end

          C_BUILD_CAP: begin
            b_setType_i = a_getType_o;
            returnvalue_o = b_setType_o | {1'b1, {`CAP_SIZE-1{1'b0}}};
            wroteCapability = 1'b1;

            exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            |exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                            |((b_getBase_o < a_getBase_o) << LENGTH_VIOLATION)
                            |((b_getTop_o > a_getTop_o) << LENGTH_VIOLATION)
                            |(((a_getPerms_o & b_getPerms_o) != b_getPerms_o) << SOFTWARE_DEFINED_VIOLATION);

            exceptions_b_o = (b_getBase_o > b_getTop_o) << LENGTH_VIOLATION;
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

            exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            |exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                            |((b_isSealed_o && b_getType_o < a_getBase_o) << LENGTH_VIOLATION)
                            |((b_isSealed_o && b_getType_o >= a_getTop_o) << LENGTH_VIOLATION);
          end

          // TODO implement later
          C_C_SEAL: begin
            a_setType_i = b_getAddr_o;
            returnvalue_o = (!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}}) ? operand_a_i : a_setType_o;
            wroteCapability = 1'b1;
             
            
            // TODO deal with exceptions
            exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            |((exceptions_a[SEAL_VIOLATION] && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}}))
                               << SEAL_VIOLATION);

            exceptions_b_o = ((exceptions_b[SEAL_VIOLATION] && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}}))<< SEAL_VIOLATION)
                            |((exceptions_b[PERMIT_SEAL_VIOLATION] && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}})) << PERMIT_SEAL_VIOLATION)
                            |((exceptions_b[LENGTH_VIOLATION] && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}})) << LENGTH_VIOLATION)
                            |((b_getAddr_o >= b_getTop_o && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}})) << LENGTH_VIOLATION)
                            |((b_getAddr_o > {`OTYPE_SIZE{1'b1}} && !(!b_isValidCap_o || b_getAddr_o == {`INTEGER_SIZE{1'b1}})) << LENGTH_VIOLATION);
          end

          C_TEST_SUBSET: begin
            returnvalue_o = a_isValidCap_o != b_isValidCap_o ?            1'b0 :
                            b_getBase_o < a_getBase_o ?                     1'b0 :
                            b_getTop_o > a_getTop_o ?                       1'b0 :
                            (b_getPerms_o & a_getPerms_o) == b_getPerms_o ? 1'b0 :
                                                                          1'b1;
            wroteCapability = 1'b0;
          end

          // TODO implement later
          STORE: begin
            // TODO
          end

          // TODO implement later
          LOAD: begin
            // TODO
          end

          CCALL: begin
            // when trying to read this using the spec, cs is my operand_a and cb is my operand_b
            // in general in the rest of this file this is the other way around, with cb being operand_a
            // and cs being operand b
            exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                            |exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                            |((a_getType_o != b_getType_o) << TYPE_VIOLATION)
                            |exceptions_a[PERMIT_EXECUTE_VIOLATION] << PERMIT_EXECUTE_VIOLATION
                            |exceptions_a[LENGTH_VIOLATION] << LENGTH_VIOLATION
                            |((a_getAddr_o >= a_getTop_o) << LENGTH_VIOLATION)
                            |(1'b1 << CALL_TRAP);

            exceptions_b_o = exceptions_b[TAG_VIOLATION] << TAG_VIOLATION
                            |exceptions_b[SEAL_VIOLATION] << SEAL_VIOLATION
                            |((b_getPerms_o[`PERMIT_EXECUTE_INDEX]) << PERMIT_EXECUTE_VIOLATION);
          end

          SOURCE_AND_DEST: begin
            case(sad_opcode_i)
              C_GET_PERM: begin
                returnvalue_o = {{`INTEGER_SIZE-`PERMS_SIZE{1'b0}}, a_getPerms_o};
                wroteCapability = 1'b0;
              end

              C_GET_TYPE: begin
                returnvalue_o = a_isSealed_o ? {{`INTEGER_SIZE-`OTYPE_SIZE{1'b0}}, a_getType_o} : {`INTEGER_SIZE{1'b1}};
                wroteCapability = 1'b0;
              end

              C_GET_BASE: begin
                returnvalue_o = a_getBase_o;
                wroteCapability = 1'b0;
              end

              C_GET_LEN: begin
                returnvalue_o = a_getLength_o[`LENGTH_SIZE-1] ? {`INTEGER_SIZE{1'b1}} : a_getLength_o[`INTEGER_SIZE-1:0];
                wroteCapability = 1'b0;
              end

              C_GET_TAG: begin
                returnvalue_o = {{`INTEGER_SIZE-1{1'b0}}, a_isValidCap_o};
                wroteCapability = 1'b0;
              end

              C_GET_SEALED: begin
                returnvalue_o = {{`INTEGER_SIZE-`OTYPE_SIZE{1'b0}}, a_isSealed_o};
                wroteCapability = 1'b0;
              end

              C_GET_OFFSET: begin
                returnvalue_o = {{`INTEGER_SIZE-`OFFSET_SIZE{1'b0}}, a_getOffset_o};
                wroteCapability = 1'b0;
              end

              C_GET_FLAGS: begin
                returnvalue_o = {{`INTEGER_SIZE-`FLAG_SIZE{1'b0}}, a_getFlags_o};
                wroteCapability = 1'b0;
              end

              C_MOVE: begin
                returnvalue_o = operand_a_i;
                wroteCapability = 1'b1;
              end

              C_CLEAR_TAG: begin
                a_setValidCap_i = 1'b0;
                returnvalue_o = a_setValidCap_o;
                wroteCapability = 1'b1;
              end

              // TODO implement later
              // TODO implement the rest of this instruction in the ID stage
              C_JALR: begin
                // in this instruction, cb is operand_b since we're actually passing pcc as the first operand

                // current implemenation of JAL and JALR:
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

                a_setAddr_i = b_getAddr_o;
                returnvalue_o = a_setAddr_o[`CAP_SIZE-1:0];

                exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                                |exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                                |exceptions_a[PERMIT_EXECUTE_VIOLATION] << PERMIT_EXECUTE_VIOLATION
                                |exceptions_a[LENGTH_VIOLATION] << LENGTH_VIOLATION
                                |((a_getAddr_o + `MIN_INSTR_BYTES > a_getTop_o) << LENGTH_VIOLATION);
                                // we don't care about trying to throw the last exception since we do support
                                // compressed instructions
                
                // we don't set wroteCapability since we're not planning on writing what we returned to
                // a register
              end

              // TODO implement elsewhere
              CLEAR: begin
              end

              C_GET_ADDR: begin
                returnvalue_o = a_getAddr_o;
                wroteCapability = 1'b0;
              end

              // TODO ask:this instruction doesn't make sense on ibex - what exception to call?
              C_FP_CLEAR: begin

              end

              default: begin
                $display("something went wrong in the ibex_alu");
              end
            endcase
          end


              default: begin
                $display("something went wrong in the ibex_alu");
              end
        endcase
      end

      C_INC_OFFSET_IMM: begin
        // TODO immediate from ibex should already be sign-extended, so might be able to just skip sign-extension stuff here
        a_setOffset_i = a_getOffset_o + (operand_b_i[`IMM_SIZE-1] ? {{`INTEGER_SIZE-`IMM_SIZE{1'b1}}, operand_b_i} : operand_b_i);
        returnvalue_o = a_setOffset_o[`CAP_SIZE] ? a_setOffset_o : a_getAddr_o + (operand_b_i[`IMM_SIZE-1] ? {{`INTEGER_SIZE-`IMM_SIZE{1'b1}}, operand_b_i} : operand_b_i);
        wroteCapability = a_setOffset_o[`CAP_SIZE];

        exceptions_a_o = exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION;
      end

      C_SET_BOUNDS_IMM: begin
        // need to truncate input since we want it to be unsigned
        // TODO there has to be a cleaner way of doing this
        a_setBounds_i = operand_b_i[`IMM_SIZE-1:0];
        returnvalue_o = a_setBounds_o[`CAP_SIZE-1:0];
        wroteCapability = 1'b1;

        exceptions_a_o = exceptions_a[TAG_VIOLATION] << TAG_VIOLATION
                        |exceptions_a[SEAL_VIOLATION] << SEAL_VIOLATION
                        |exceptions_a[LENGTH_VIOLATION] << LENGTH_VIOLATION
                        |((a_getAddr_o+operand_b_i[11:0] > a_getTop_o) << LENGTH_VIOLATION);
      end

      default: begin
        $display("something went wrong in the ibex_alu");
      end

    endcase
  end





// stuff i think the CHERI ALU needs to do:
/*  getPerm
    getType
    getBase
    getLen
    getTag
    getSealed
    getOffset
    getFlags
    getAddr







*/  





/*

module_wrap64_nullCap nullCap_3 (wrap64_nullCap);

mmodule module_wrap64_almightyCap(wrap64_almightyCap);
odule module_wrap64_almightyCap(wrap64_almightyCap);




module_wrap64_getAddr getAddr_1 (wrap64_getAddr_cap,
			     wrap64_getAddr);
module_wrap64_getAddr getAddr_2 (wrap64_getAddr_cap,
			     wrap64_getAddr);
module_wrap64_getAddr getAddr_3 (wrap64_getAddr_cap,
			     wrap64_getAddr);

module_wrap64_fromMem fromMem_1 (wrap64_fromMem_mem_cap,
			     wrap64_fromMem);
module_wrap64_fromMem fromMem_2 (wrap64_fromMem_mem_cap,
			     wrap64_fromMem);
module_wrap64_fromMem fromMem_3 (wrap64_fromMem_mem_cap,
			     wrap64_fromMem);





module_wrap64_validAsType validAsType_1 (wrap64_validAsType_dummy,
				 wrap64_validAsType_checkType,
				 wrap64_validAsType);
module_wrap64_validAsType validAsType_2 (wrap64_validAsType_dummy,
				 wrap64_validAsType_checkType,
				 wrap64_validAsType);
module_wrap64_validAsType validAsType_3 (wrap64_validAsType_dummy,
				 wrap64_validAsType_checkType,
				 wrap64_validAsType);

module_wrap64_toMem toMem_1 (wrap64_toMem_cap,
			   wrap64_toMem);
module_wrap64_toMem toMem_2 (wrap64_toMem_cap,
			   wrap64_toMem);
module_wrap64_toMem toMem_3 (wrap64_toMem_cap,
			   wrap64_toMem);

module_wrap64_setValidCap setValidCap_1 (wrap64_setValidCap_cap,
				 wrap64_setValidCap_valid,
				 wrap64_setValidCap);
module_wrap64_setValidCap setValidCap_2 (wrap64_setValidCap_cap,
				 wrap64_setValidCap_valid,
				 wrap64_setValidCap);
module_wrap64_setValidCap setValidCap_3 (wrap64_setValidCap_cap,
				 wrap64_setValidCap_valid,
				 wrap64_setValidCap);

module_wrap64_setType setType_1 (wrap64_setType_cap,
			     wrap64_setType_otype,
			     wrap64_setType);
module_wrap64_setType setType_2 (wrap64_setType_cap,
			     wrap64_setType_otype,
			     wrap64_setType);
module_wrap64_setType setType_3 (wrap64_setType_cap,
			     wrap64_setType_otype,
			     wrap64_setType);

module_wrap64_setSoftPerms setSoftPerms_1 (wrap64_setSoftPerms_cap,
				  wrap64_setSoftPerms_softperms,
				  wrap64_setSoftPerms);
module_wrap64_setSoftPerms setSoftPerms_2 (wrap64_setSoftPerms_cap,
				  wrap64_setSoftPerms_softperms,
				  wrap64_setSoftPerms);
module_wrap64_setSoftPerms setSoftPerms_3 (wrap64_setSoftPerms_cap,
				  wrap64_setSoftPerms_softperms,
				  wrap64_setSoftPerms);

module_wrap64_setPerms setPerms_1 (wrap64_setPerms_cap,
			      wrap64_setPerms_perms,
			      wrap64_setPerms);
module_wrap64_setPerms setPerms_2 (wrap64_setPerms_cap,
			      wrap64_setPerms_perms,
			      wrap64_setPerms);
module_wrap64_setPerms setPerms_3 (wrap64_setPerms_cap,
			      wrap64_setPerms_perms,
			      wrap64_setPerms);

module_wrap64_setOffset setOffset_1 (wrap64_setOffset_cap,
			       wrap64_setOffset_offset,
			       wrap64_setOffset);
module_wrap64_setOffset setOffset_2 (wrap64_setOffset_cap,
			       wrap64_setOffset_offset,
			       wrap64_setOffset);
module_wrap64_setOffset setOffset_3 (wrap64_setOffset_cap,
			       wrap64_setOffset_offset,
			       wrap64_setOffset);

module_wrap64_setHardPerms setHardPerms_1 (wrap64_setHardPerms_cap,
				  wrap64_setHardPerms_hardperms,
				  wrap64_setHardPerms);
module_wrap64_setHardPerms setHardPerms_2 (wrap64_setHardPerms_cap,
				  wrap64_setHardPerms_hardperms,
				  wrap64_setHardPerms);
module_wrap64_setHardPerms setHardPerms_3 (wrap64_setHardPerms_cap,
				  wrap64_setHardPerms_hardperms,
				  wrap64_setHardPerms);

module_wrap64_setFlags setFlags_1 (wrap64_setFlags_cap,
			      wrap64_setFlags);
module_wrap64_setFlags setFlags_2 (wrap64_setFlags_cap,
			      wrap64_setFlags);
module_wrap64_setFlags setFlags_3 (wrap64_setFlags_cap,
			      wrap64_setFlags);

module_wrap64_setBounds setBounds_1 (wrap64_setBounds_cap,
			       wrap64_setBounds_length,
			       wrap64_setBounds);
module_wrap64_setBounds setBounds_2 (wrap64_setBounds_cap,
			       wrap64_setBounds_length,
			       wrap64_setBounds);
module_wrap64_setBounds setBounds_3 (wrap64_setBounds_cap,
			       wrap64_setBounds_length,
			       wrap64_setBounds);

module_wrap64_setAddr setAddr_1 (wrap64_setAddr_cap,
			     wrap64_setAddr_addr,
			     wrap64_setAddr);
module_wrap64_setAddr setAddr_2 (wrap64_setAddr_cap,
			     wrap64_setAddr_addr,
			     wrap64_setAddr);
module_wrap64_setAddr setAddr_3 (wrap64_setAddr_cap,
			     wrap64_setAddr_addr,
			     wrap64_setAddr);
module_wrap64_nullWithAddr nullWithAddr_1 (wrap64_nullWithAddr_addr,
				  wrap64_nullWithAddr);
module_wrap64_nullWithAddr nullWithAddr_2 (wrap64_nullWithAddr_addr,
				  wrap64_nullWithAddr);
module_wrap64_isValidCap isValidCap_1 (wrap64_isValidCap_cap,
				wrap64_isValidCap);
module_wrap64_isValidCap isValidCap_2 (wrap64_isValidCap_cap,
				wrap64_isValidCap);
module_wrap64_isValidCap isValidCap_3 (wrap64_isValidCap_cap,
				wrap64_isValidCap);
module_wrap64_isSentry isSentry_1 (wrap64_isSentry_cap,
			      wrap64_isSentry);
module_wrap64_isSentry isSentry_2 (wrap64_isSentry_cap,
			      wrap64_isSentry);
module_wrap64_isSentry isSentry_3 (wrap64_isSentry_cap,
			      wrap64_isSentry);
module_wrap64_isSealedWithType isSealedWithType_1 (wrap64_isSealedWithType_cap,
				      wrap64_isSealedWithType);
module_wrap64_isSealedWithType isSealedWithType_2 (wrap64_isSealedWithType_cap,
				      wrap64_isSealedWithType);
module_wrap64_isSealedWithType isSealedWithType_3 (wrap64_isSealedWithType_cap,
				      wrap64_isSealedWithType);
module_wrap64_isSealed isSealed_1 (wrap64_isSealed_cap,
			      wrap64_isSealed);
module_wrap64_isSealed isSealed_2 (wrap64_isSealed_cap,
			      wrap64_isSealed);
module_wrap64_isSealed isSealed_3 (wrap64_isSealed_cap,
			      wrap64_isSealed);
module_wrap64_isInBounds isInBounds_1 (wrap64_isInBounds_cap,
				wrap64_isInBounds_isTopIncluded,
				wrap64_isInBounds);
module_wrap64_isInBounds isInBounds_2 (wrap64_isInBounds_cap,
				wrap64_isInBounds_isTopIncluded,
				wrap64_isInBounds);
module_wrap64_isInBounds isInBounds_3 (wrap64_isInBounds_cap,
				wrap64_isInBounds_isTopIncluded,
				wrap64_isInBounds);
module_wrap64_getType getType_1 (wrap64_getType_cap,
			     wrap64_getType);
module_wrap64_getType getType_2 (wrap64_getType_cap,
			     wrap64_getType);
module_wrap64_getType getType_3 (wrap64_getType_cap,
			     wrap64_getType);
module_wrap64_getTop getTop_1 (wrap64_getTop_cap,
			    wrap64_getTop);
module_wrap64_getTop getTop_2 (wrap64_getTop_cap,
			    wrap64_getTop);
module_wrap64_getTop getTop_3 (wrap64_getTop_cap,
			    wrap64_getTop);

module_wrap64_getSoftPerms getSoftPerms_1 (wrap64_getSoftPerms_cap,
				  wrap64_getSoftPerms);
module_wrap64_getSoftPerms getSoftPerms_2 (wrap64_getSoftPerms_cap,
				  wrap64_getSoftPerms);
module_wrap64_getSoftPerms getSoftPerms_3 (wrap64_getSoftPerms_cap,
				  wrap64_getSoftPerms);

module_wrap64_getPerms getPerms_1 (wrap64_getPerms_cap,
			      wrap64_getPerms);
module_wrap64_getPerms getPerms_2 (wrap64_getPerms_cap,
			      wrap64_getPerms);
module_wrap64_getPerms getPerms_3 (wrap64_getPerms_cap,
			      wrap64_getPerms);

module_wrap64_getOffset getOffset_1 (wrap64_getOffset_cap,
			       wrap64_getOffset);
module_wrap64_getOffset getOffset_2 (wrap64_getOffset_cap,
			       wrap64_getOffset);
module_wrap64_getOffset getOffset_3 (wrap64_getOffset_cap,
			       wrap64_getOffset);

module_wrap64_getLength getLength_1 (wrap64_getLength_cap,
			       wrap64_getLength);
module_wrap64_getLength getLength_2 (wrap64_getLength_cap,
			       wrap64_getLength);
module_wrap64_getLength getLength_3 (wrap64_getLength_cap,
			       wrap64_getLength);

module_wrap64_getKind getKind_1 (wrap64_getKind_cap,
			     wrap64_getKind);
module_wrap64_getKind getKind_2 (wrap64_getKind_cap,
			     wrap64_getKind);
module_wrap64_getKind getKind_3 (wrap64_getKind_cap,
			     wrap64_getKind);

module_wrap64_getHardPerms getHardPerms_1 (wrap64_getHardPerms_cap,
				  wrap64_getHardPerms);
module_wrap64_getHardPerms getHardPerms_2 (wrap64_getHardPerms_cap,
				  wrap64_getHardPerms);
module_wrap64_getHardPerms getHardPerms_3 (wrap64_getHardPerms_cap,
				  wrap64_getHardPerms);


module_wrap64_getBase getBase_1 (wrap64_getBase_cap,
			     wrap64_getBase);
module_wrap64_getBase getBase_2 (wrap64_getBase_cap,
			     wrap64_getBase);
module_wrap64_getBase getBase_3 (wrap64_getBase_cap,
			     wrap64_getBase);






module_wrap64_getFlags getFlags_a_module (wrap64_getFlags_cap,
			      wrap64_getFlags);
module_wrap64_getFlags getFlags_b_module (wrap64_getFlags_cap,
			      wrap64_getFlags);
module_wrap64_getFlags getFlags_pcc_module (wrap64_getFlags_cap,
			      wrap64_getFlags);
module_wrap64_getFlags getFlags_ddc_module (wrap64_getFlags_cap,
			      wrap64_getFlags);





// TODO implement all these things
// TODO implement all these things for operand b

module_wrap64_getAddr module_getAddr_a (
    .wrap64_getAddr_cap(operand_a),
    .wrap64_getAddr(a_getAddr));



module_wrap64_getBase module_getBase_a (
    .wrap64_getBase_cap(operand_a),
    .wrap64_getBase(a_getBase));



module_wrap64_getFlags module_getFlags_a (
  .wrap64_getFlags_cap(operand_a),
    .wrap64_getFlags(a_getFlags));



module_wrap64_getHardPerms module_getHardPerms_a (
  .wrap64_getHardPerms_cap(operand_a),
    .wrap64_getHardPerms(a_getHardPerms));



module_wrap64_getKind module_getKind_a (
  .wrap64_getKind_cap(operand_a),
    .wrap64_getKind(a_getKind));



module_wrap64_getLength module_getLength_a (
  .wrap64_getLength_cap(operand_a),
    .wrap64_getLength(a_getLength));



module_wrap64_getOffset module_getOffset_a (
  .wrap64_getOffset_cap(operand_a),
    .wrap64_getOffset(a_getOffset));



module_wrap64_getPerms module_wrap64_getPerms_a (
  .wrap64_getPerms_cap(operand_a),
    .wrap64_getPerms(a_getPerms));



module_wrap64_getSoftPerms module_wrap64_getSoftPerms_a (
  .wrap64_getSoftPerms_cap(operand_a),
    .wrap64_getSoftPerms(a_getSoftPerms));



module_wrap64_getTop module_wrap64_getTop_a (
  .wrap64_getTop_cap(operand_a),
    .wrap64_getTop(a_getTop));



module_wrap64_getType module_wrap64_getType_a (
  .wrap64_getType_cap(operand_a),
    .wrap64_getType(a_getType));



module_wrap64_isInBounds module_wrap64_isInBounds_a (
  .wrap64_isInBounds_cap(operand_a),
    .wrap64_isInBounds_isTopIncluded(a_isInBounds_isTopIncluded),
    .wrap64_isInBounds(a_isInBounds));

module_wrap64_isSealed module_wrap64_isSealed_a (
  .wrap64_isSealed_cap(operand_a),
    .wrap64_isSealed(a_isSealed));



module_wrap64_isSealedWithType module_wrap64_isSealedWithType_a (
  .wrap64_isSealedWithType_cap(operand_a),
    .wrap64_isSealedWithType(a_isSealedWithType));



module_wrap64_isSentry module_wrap64_isSentry_a (
  .wrap64_isSentry_cap(operand_a),
    .wrap64_isSentry(a_isSentry));



module_wrap64_isValidCap module_wrap64_isValidCap_a (
  .wrap64_isValidCap_cap(operand_a),
    .wrap64_isValidCap(a_isValidCap));



module_wrap64_setAddr module_wrap64_setAddr_a (
  .wrap64_setAddr_cap(operand_a),
    .wrap64_setAddr_addr(a_setAddr_addr),
    .wrap64_setAddr(a_setAddr));


module_wrap64_setBounds module_wrap64_setBounds_a (
  .wrap64_setBounds_cap(operand_a),
    .wrap64_setBounds_length(a_setBounds_length),
    .wrap64_setBounds(a_setBounds));


module_wrap64_setFlags module_wrap64_setFlags_a (
  .wrap64_setFlags_cap(operand_a),
    .wrap64_setFlags_flags(a_setFlags_flags),
    .wrap64_setFlags(a_setFlags));


module_wrap64_setHardPerms module_wrap64_setHardPerms_a (
  .wrap64_setHardPerms_cap(operand_a),
    .wrap64_setHardPerms_hardperms(a_setHardPerms_hardperms),
    .wrap64_setHardPerms(a_setHardPerms));


module_wrap64_setOffset module_wrap64_setOffset_a (
  .wrap64_setOffset_cap(operand_a),
    .wrap64_setOffset_offset(a_setOffset_offset),
    .wrap64_setOffset(a_setOffset));


module_wrap64_setPerms module_wrap64_setPerms_a (
  .wrap64_setPerms_cap(operand_a),
    .wrap64_setPerms_perms(a_setPerms_perms),
    .wrap64_setPerms(a_setPerms));


module_wrap64_setSoftPerms module_wrap64_setSoftPerms_a (
  .wrap64_setSoftPerms_cap(operand_a),
    .wrap64_setSoftPerms_softperms(a_setSoftPerms_softperms),
    .wrap64_setSoftPerms(a_setSoftPerms));


module_wrap64_setType module_wrap64_setType_a (
  .wrap64_setType_cap(operand_a),
    .wrap64_setType_otype(a_setType_otype),
    .wrap64_setType(a_setType));


module_wrap64_setValidCap module_wrap64_setValidCap_a (
  .wrap64_setValidCap_cap(operand_a),
    .wrap64_setValidCap_valid(a_setValidCap_valid),
    .wrap64_setValidCap(a_setValidCap));


module_wrap64_validAsType module_wrap64_validAsType_a (wrap64_validAsType_dummy,
				 wrap64_validAsType_checkType,
				 wrap64_validAsType);

*/





// TODO need to make all of these the correct size

logic [`CAP_SIZE-1:0] a_setBounds_i;
logic [`CAP_SIZE:0] a_setBounds_o;
module_wrap64_setBounds module_wrap64_setBounds_a (
    .wrap64_setBounds_cap(operand_a_i),
    .wrap64_setBounds_length(a_setBounds_i),
    .wrap64_setBounds(a_setBounds_o));


logic [`CAP_SIZE-1:0] a_getAddr_o;
module_wrap64_getAddr module_getAddr_a (
    .wrap64_getAddr_cap(operand_a_i),
    .wrap64_getAddr(a_getAddr_o));

logic [`CAP_SIZE-1:0] b_getAddr_o;
module_wrap64_getAddr module_getAddr_b (
    .wrap64_getAddr_cap(operand_b_i),
    .wrap64_getAddr(b_getAddr_o));

logic [`CAP_SIZE-1:0] a_getTop_o;
module_wrap64_getTop module_wrap64_getTop_a (
  .wrap64_getTop_cap(operand_a_i),
    .wrap64_getTop(a_getTop_o));

logic [`CAP_SIZE-1:0] b_getTop_o;
module_wrap64_getTop module_wrap64_getTop_b (
  .wrap64_getTop_cap(operand_b_i),
    .wrap64_getTop(b_getTop_o));

logic [`CAP_SIZE-1:0] a_setType_i;
logic [`CAP_SIZE:0] a_setType_o;
module_wrap64_setType module_wrap64_setType_a (
  .wrap64_setType_cap(operand_a_i),
    .wrap64_setType_otype(a_setType_i),
    .wrap64_setType(a_setType_o));

logic [`CAP_SIZE-1:0] b_setType_i;
logic [`CAP_SIZE:0] b_setType_o;
module_wrap64_setType module_wrap64_setType_b (
  .wrap64_setType_cap(operand_b_i),
    .wrap64_setType_otype(b_setType_i),
    .wrap64_setType(b_setType_o));

logic [`CAP_SIZE-1:0] a_getPerms_o;
module_wrap64_getPerms module_wrap64_getPerms_a (
  .wrap64_getPerms_cap(operand_a_i),
    .wrap64_getPerms(a_getPerms_o));

logic [`CAP_SIZE-1:0] b_getPerms_o;
module_wrap64_getPerms module_wrap64_getPerms_b (
  .wrap64_getPerms_cap(operand_b_i),
    .wrap64_getPerms(b_getPerms_o));


logic [`CAP_SIZE-1:0] a_setPerms_i;
logic [`CAP_SIZE-1:0] a_setPerms_o;
module_wrap64_setPerms module_wrap64_setPerms_a (
  .wrap64_setPerms_cap(operand_a_i),
    .wrap64_setPerms_perms(a_setPerms_i),
    .wrap64_setPerms(a_setPerms_o));


logic [`CAP_SIZE-1:0] b_setPerms_i;
logic [`CAP_SIZE-1:0] b_setPerms_o;
module_wrap64_setPerms module_wrap64_setPerms_b (
  .wrap64_setPerms_cap(operand_b_i),
    .wrap64_setPerms_perms(b_setPerms_i),
    .wrap64_setPerms(b_setPerms_o));

logic [`CAP_SIZE-1:0] a_setFlags_i;
logic [`CAP_SIZE-1:0] a_setFlags_o;
module_wrap64_setFlags module_wrap64_setFlags_a (
  .wrap64_setFlags_cap(operand_a_i),
    .wrap64_setFlags_flags(a_setFlags_i),
    .wrap64_setFlags(a_setFlags_o));

logic [`CAP_SIZE-1:0] a_setOffset_i;
logic [`CAP_SIZE:0] a_setOffset_o;
module_wrap64_setOffset module_wrap64_setOffset_a (
  .wrap64_setOffset_cap(operand_a_i),
    .wrap64_setOffset_offset(a_setOffset_i),
    .wrap64_setOffset(a_setOffset_o));

logic [`CAP_SIZE-1:0] a_getBase_o;
module_wrap64_getBase module_getBase_a (
    .wrap64_getBase_cap(operand_a_i),
    .wrap64_getBase(a_getBase_o));

logic [`CAP_SIZE-1:0] b_getBase_o;
module_wrap64_getBase module_getBase_b (
    .wrap64_getBase_cap(operand_b_i),
    .wrap64_getBase(b_getBase_o));

logic [`CAP_SIZE-1:0] a_getOffset_o;
module_wrap64_getOffset module_getOffset_a (
  .wrap64_getOffset_cap(operand_a_i),
    .wrap64_getOffset(a_getOffset_o));

logic [`CAP_SIZE-1:0] b_getOffset_o;
module_wrap64_getOffset module_getOffset_b (
  .wrap64_getOffset_cap(operand_b_i),
    .wrap64_getOffset(b_getOffset_o));


logic [`CAP_SIZE-1:0] a_isValidCap_o;
module_wrap64_isValidCap module_wrap64_isValidCap_a (
  .wrap64_isValidCap_cap(operand_a_i),
    .wrap64_isValidCap(a_isValidCap_o));

logic [`CAP_SIZE-1:0] b_isValidCap_o;
module_wrap64_isValidCap module_wrap64_isValidCap_b (
  .wrap64_isValidCap_cap(operand_b_i),
    .wrap64_isValidCap(b_isValidCap_o));


logic [`CAP_SIZE-1:0] nullWithAddr_i;
logic [`CAP_SIZE-1:0] nullWithAddr_o;
module_wrap64_nullWithAddr nullWithAddr (.wrap64_nullWithAddr_addr(nullWithAddr_i),
				  .wrap64_nullWithAddr(nullWithAddr_o));


logic [`CAP_SIZE-1:0] a_isSealed_o;
module_wrap64_isSealed module_wrap64_isSealed_a (
  .wrap64_isSealed_cap(operand_a_i),
    .wrap64_isSealed(a_isSealed_o));

logic [`CAP_SIZE-1:0] b_isSealed_o;
module_wrap64_isSealed module_wrap64_isSealed_b (
  .wrap64_isSealed_cap(operand_b_i),
    .wrap64_isSealed(b_isSealed_o));


logic [`CAP_SIZE-1:0] a_getType_o;
module_wrap64_getType module_wrap64_getType_a (
  .wrap64_getType_cap(operand_a_i),
    .wrap64_getType(a_getType_o));

logic [`CAP_SIZE-1:0] b_getType_o;
module_wrap64_getType module_wrap64_getType_b (
  .wrap64_getType_cap(operand_b_i),
    .wrap64_getType(b_getType_o));


logic [`CAP_SIZE-1:0] a_getLength_o;
module_wrap64_getLength module_getLength_a (
  .wrap64_getLength_cap(operand_a_i),
    .wrap64_getLength(a_getLength_o));

logic [`CAP_SIZE-1:0] a_getFlags_o;
module_wrap64_getFlags module_getFlags_a (
  .wrap64_getFlags_cap(operand_a_i),
    .wrap64_getFlags(a_getFlags_o));

logic [`CAP_SIZE-1:0] a_setValidCap_i;
logic [`CAP_SIZE-1:0] a_setValidCap_o;
module_wrap64_setValidCap module_wrap64_setValidCap_a (
  .wrap64_setValidCap_cap(operand_a_i),
    .wrap64_setValidCap_valid(a_setValidCap_i),
    .wrap64_setValidCap(a_setValidCap_o));

logic [`CAP_SIZE-1:0] b_setValidCap_i;
logic [`CAP_SIZE-1:0] b_setValidCap_o;
module_wrap64_setValidCap module_wrap64_setValidCap_b (
  .wrap64_setValidCap_cap(operand_b_i),
    .wrap64_setValidCap_valid(b_setValidCap_i),
    .wrap64_setValidCap(b_setValidCap_o));

logic [`CAP_SIZE-1:0] a_setAddr_i;
logic [`CAP_SIZE:0] a_setAddr_o;
module_wrap64_setAddr module_wrap64_setAddr_a (
                .wrap64_setAddr_cap(operand_a_i),
			    .wrap64_setAddr_addr(a_setAddr_i),
			    .wrap64_setAddr(a_setAddr_o));














  // TODO
  // strictly speaking, some of the exceptions that are being set after isSealed and
  // isValidCap would need to be &&'d with the negative of the ones above them
  // (ie a_isValidCap_o && !a_isSealed_o && a_CURSOR_o < a_isSealed_o)
  // this may not actually be needed because exceptions have priorities
  // also need to have two vectors which hold exceptions: one for operand a and one for operand b
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
    
    // checks that the address is not smaller than the base
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

  end






endmodule
