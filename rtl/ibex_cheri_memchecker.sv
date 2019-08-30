// TODO implement an MMU to do bounds checking on capabilities
// the address inputs for this will have to include both a capability and an offset
// the new capability can't be calculated in the ALU because changing the offset can break the
// bounds, but we need the bounds to remain intact so we can check the address against them
// the memory width for the mmu will be 65 bits

`define CAP_SIZE 93
`define INT_SIZE 32
`define EXCEPTION_SIZE 22

// LQddc uses load_cap_via_cap. This means that any quads that are read must be quad-aligned, right?
// do i use those semantics for LDddc in ibex?
// the way ldcap should work is by reading in a double. if the address is capability-aligned then you load in
// the tag as well, and if it wasn't you set the tag to 0.
module ibex_cheri_memchecker #(
    // 1 means this is for data, 0 means this is for instructions
    parameter DATA_MEM = 1'b1
) (
    //inputs:
    // need something that provides authority
    // need the base address
    // need the offset (only for LoadCap and StoreCap)
    // need to know if the instruction is trying to do a capability access
    // need to know if the instruction is trying to do a read or write
    // these don't necessarily have to be mutually exclusive, and the input capability
    // can also be the thing that provides the base address
    // If trying to avoid adding in here to get the effective address and implementing that using
    // the cincoffsetimmediate ALU operation, need to separately provide the capability and the
    // authority, but don't need the offset (implicity in the effective address)
    // if we take in the effective address then we don't need to return it from here, otherwise
    // we do need to return the effective address


    // first implementation:
    // pass in a capability to provide the base address and the authority,
    // and separately an offset to be added to the base address

    /*
      This module also needs to modify the data (since we want to clear the tag sometimes) so we need to get the data
      into and out of here as well as the address and authority
    */

    input logic [`CAP_SIZE-1:0] cap_base_i,
    // TODO decide if this should be an address or an offset from the capability
    //  for now, decided on it being an offset from the base of the capability
    input logic [`INT_SIZE-1:0] address_i,
    input logic [63:0] mem_data_i,
    input logic        mem_tag_i,
    input logic [`CAP_SIZE-1:0] lsu_data_i,
    input logic [1:0] data_type_i,
    input logic write_i,
    input logic access_capability_i,
    input logic [7:0] data_be_i,

    input logic [2:0] offset,

    output logic [63:0] mem_data_o,
    output logic        mem_tag_o,
    output logic [`CAP_SIZE-1:0] lsu_data_o,
    output logic [7:0] data_be_o,
    output logic [`EXCEPTION_SIZE-1:0] cheri_mem_exc_o
);
  import ibex_defines::*;

  logic [3:0] data_size;
  assign data_size = data_type_i == 2'b00 ? 4'h4 : // Word
                     data_type_i == 2'b01 ? 4'h2 : // Halfword
                     data_type_i == 2'b10 ? 4'h1 : // Byte
                                            4'h8;  // Double

  assign data_be_o = access_capability_i ? 8'hff : data_be_i;

  assign cheri_mem_exc_o[TAG_VIOLATION] = !base_isValidCap_o;
  assign cheri_mem_exc_o[SEAL_VIOLATION] = base_isSealed_o;
  assign cheri_mem_exc_o[PERMIT_LOAD_VIOLATION] = !write_i && !cap_base_i_getPerms_o[2];
  assign cheri_mem_exc_o[PERMIT_STORE_VIOLATION] = write_i && !cap_base_i_getPerms_o[3];
  assign cheri_mem_exc_o[PERMIT_EXECUTE_VIOLATION] = DATA_MEM == 1'b0 && !cap_base_i_getPerms_o[1];

  // TODO should load/store capability violations ever happen?

  assign cheri_mem_exc_o[LENGTH_VIOLATION] = address_i < base_getBase_o
                                           || address_i + data_size > base_getTop_o;

  // TODO remove
  // temporarily throw trap on an unaligned access
  //assign cheri_mem_exc_o[MMU_PROHIBITS_STORE_VIOLATION] = access_capability_i && |(address_i[2:0]);
  assign cheri_mem_exc_o[MMU_PROHIBITS_STORE_VIOLATION] = access_capability_i && |offset;

  // if this is a data memory checker, we need to make sure that if we're trying to read a capability
  // we check that it's properly aligned.

  // read stuff
  always_comb begin
    // TODO either set it to '0 here or use a setIsValidCap. using setIsValidCap means that if the capability
    // layout changes i only need to update dependencies
    lsu_data_o = access_capability_i ? (!(|address_i[2:0]) ? fromMem_o
                                                           : {1'b0, fromMem_o[`CAP_SIZE-2:0]})
                                     : {mem_tag_i, mem_data_i};
  end

  always_comb begin
    // TODO either set it to '0 here or use a setIsValidCap. using setIsValidCap means that if the capability
    // layout changes i only need to update dependencies
    toMem_i = {access_capability_i && !(|address_i[2:0]) ? lsu_data_i[`CAP_SIZE-1] : '0, lsu_data_i[`CAP_SIZE-2:0]};
    mem_data_o = access_capability_i ? toMem_o[63:0] : lsu_data_i[63:0];
    mem_tag_o = access_capability_i ? toMem_o[64] : lsu_data_i[64];
  end


logic [`CAP_SIZE-1:0] fromMem_o;
module_wrap64_fromMem module_fromMem ({mem_tag_i, mem_data_i},
			     fromMem_o);

logic[`CAP_SIZE-1:0] toMem_i;
logic[64:0] toMem_o;
module_wrap64_toMem module_toMem (toMem_i,
			   toMem_o);



logic [`CAP_SIZE-1:0] base_getAddr_o;
module_wrap64_getAddr module_getAddr_a (
    .wrap64_getAddr_cap(cap_base_i),
    .wrap64_getAddr(base_getAddr_o));

logic [`CAP_SIZE-1:0] base_isValidCap_o;
module_wrap64_isValidCap module_wrap64_isValidCap_a (
  .wrap64_isValidCap_cap(cap_base_i),
    .wrap64_isValidCap(base_isValidCap_o));

logic [`CAP_SIZE-1:0] base_isSealed_o;
module_wrap64_isSealed module_wrap64_isSealed_a (
  .wrap64_isSealed_cap(cap_base_i),
    .wrap64_isSealed(base_isSealed_o));

logic [`CAP_SIZE-1:0] base_getBase_o;
module_wrap64_getBase module_getBase_b (
    .wrap64_getBase_cap(cap_base_i),
    .wrap64_getBase(base_getBase_o));

logic [`CAP_SIZE-1:0] base_getTop_o;
module_wrap64_getTop module_wrap64_getTop_b (
  .wrap64_getTop_cap(cap_base_i),
    .wrap64_getTop(base_getTop_o));

logic [`CAP_SIZE-1:0] cap_base_i_getPerms_o;
module_wrap64_getPerms module_wrap64_getPerms_cap_base_i (
  .wrap64_getPerms_cap(cap_base_i),
    .wrap64_getPerms(cap_base_i_getPerms_o));




endmodule
