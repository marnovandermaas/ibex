// Copyright lowRISC contributors.
// Copyright 2017 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Matthias Baer - baermatt@student.ethz.ch                   //
//                                                                            //
// Additional contributions by:                                               //
//                 Sven Stucki - svstucki@student.ethz.ch                     //
//                                                                            //
//                                                                            //
// Design Name:    RISC-V processor core                                      //
// Project Name:   ibex                                                       //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Defines for various constants used by the processor core.  //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

/**
 * Defines for various constants used by the processor core
 */
package ibex_defines;


/////////////
// Opcodes //
/////////////

typedef enum logic [6:0] {
  OPCODE_LOAD     = 7'h03,
  OPCODE_MISC_MEM = 7'h0f,
  OPCODE_OP_IMM   = 7'h13,
  OPCODE_AUIPC    = 7'h17,
  OPCODE_STORE    = 7'h23,
  OPCODE_OP       = 7'h33,
  OPCODE_LUI      = 7'h37,
  OPCODE_CHERI    = 7'h5b,
  OPCODE_BRANCH   = 7'h63,
  OPCODE_JALR     = 7'h67,
  OPCODE_JAL      = 7'h6f,
  OPCODE_SYSTEM   = 7'h73
} opcode_e;


////////////////////
// ALU operations //
////////////////////

typedef enum logic [4:0] {
  // Arithmetics
  ALU_ADD,
  ALU_SUB,

  // Logics
  ALU_XOR,
  ALU_OR,
  ALU_AND,

  // Shifts
  ALU_SRA,
  ALU_SRL,
  ALU_SLL,

  // Comparisons
  ALU_LT,
  ALU_LTU,
  ALU_LE,
  ALU_LEU,
  ALU_GT,
  ALU_GTU,
  ALU_GE,
  ALU_GEU,
  ALU_EQ,
  ALU_NE,

  // Set lower than
  ALU_SLT,
  ALU_SLTU,
  ALU_SLET,
  ALU_SLETU
} alu_op_e;

typedef enum logic [1:0] {
  // Multiplier/divider
  MD_OP_MULL,
  MD_OP_MULH,
  MD_OP_DIV,
  MD_OP_REM
} md_op_e;

//////////////////////
// CHERI operations //
//////////////////////

typedef enum logic [2:0] {
  THREE_OP          = 3'h0,
  C_INC_OFFSET_IMM  = 3'h1,
  C_SET_BOUNDS_IMM  = 3'h2
} cheri_base_opcode_e;

// THREE_OPS
typedef enum logic [6:0] {
  C_SPECIAL_RW        = 7'h01,
  C_SET_BOUNDS        = 7'h08,
  C_SET_BOUNDS_EXACT  = 7'h09,
  C_SEAL              = 7'h0B,
  C_UNSEAL            = 7'h0C,
  C_AND_PERM          = 7'h0D,
  C_SET_FLAGS         = 7'h0E,
  C_SET_OFFSET        = 7'h0F,
  C_SET_ADDR          = 7'h10,
  C_INC_OFFSET        = 7'h11,
  C_TO_PTR            = 7'h12,
  C_FROM_PTR          = 7'h13,
  C_SUB               = 7'h14,
  C_BUILD_CAP         = 7'h1D,
  C_COPY_TYPE         = 7'h1E,
  C_C_SEAL            = 7'h1F,
  C_TEST_SUBSET       = 7'h20,
  STORE               = 7'h7C,
  LOAD                = 7'h7D,
  CCALL               = 7'h7E,
  SOURCE_AND_DEST     = 7'h7F
} cheri_threeop_funct7_e;

// STORES
typedef enum logic [4:0] {
  SB_DDC = 5'h00,
  SH_DDC = 5'h01,
  SW_DDC = 5'h02,
  SD_DDC = 5'h03,
  SQ_DDC = 5'h04,
  SB_CAP = 5'h08,
  SH_CAP = 5'h09,
  SW_CAP = 5'h0A,
  SD_CAP = 5'h0B,
  SQ_CAP = 5'h0C
} cheri_store_funct5_e;

// LOADS
typedef enum logic [4:0] {
  LB_DDC  = 5'h00,
  LH_DDC  = 5'h01,
  LW_DDC  = 5'h02,
  LD_DDC  = 5'h03,
  LBU_DDC = 5'h04,
  LHU_DDC = 5'h05,
  LWU_DDC = 5'h06,
  LB_CAP  = 5'h08,
  LH_CAP  = 5'h09,
  LW_CAP  = 5'h0A,
  LD_CAP  = 5'h0B,
  LBU_CAP = 5'h0C,
  LHU_CAP = 5'h0D,
  LWU_CAP = 5'h0E,
  LQ_DDC  = 5'h17,
  LQ_CAP  = 5'h1F
} cheri_load_funct5_e;

typedef enum logic [4:0] {
  C_GET_PERM    = 5'h00,
  C_GET_TYPE    = 5'h01,
  C_GET_BASE    = 5'h02,
  C_GET_LEN     = 5'h03,
  C_GET_TAG     = 5'h04,
  C_GET_SEALED  = 5'h05,
  C_GET_OFFSET  = 5'h06,
  C_GET_FLAGS   = 5'h07,
  C_MOVE        = 5'h0A,
  C_CLEAR_TAG   = 5'h0B,
  C_JALR        = 5'h0C,
  CLEAR         = 5'h0D,
  C_GET_ADDR    = 5'h0F,
  C_FP_CLEAR    = 5'h10,
  ONE_OP        = 5'h1f
} cheri_s_a_d_funct5_e;

//////////////////////
// CHERI Exceptions //
//////////////////////

typedef enum logic [4:0] {
  ACCESS_SYSTEM_REGISTERS_VIOLATION,
  TAG_VIOLATION,
  SEAL_VIOLATION,
  TYPE_VIOLATION,
  PERMIT_SEAL_VIOLATION,
  PERMIT_CCALL_VIOLATION,
  ACCESS_CCALL_IDC_VIOLATION,
  PERMIT_UNSEAL_VIOLATION,
  PERMIT_SETSID_VIOLATION,
  PERMIT_EXECUTE_VIOLATION,
  PERMIT_LOAD_VIOLATION,
  PERMIT_STORE_VIOLATION,
  PERMIT_LOAD_CAPABILITY_VIOLATION,
  PERMIT_STORE_CAPABILITY_VIOLATION,
  PERMIT_STORE_LOCAL_CAPABILITY_VIOLATION,
  GLOBAL_VIOLATION,
  LENGTH_VIOLATION,
  INEXACT_BOUNDS_VIOLATION,
  SOFTWARE_DEFINED_VIOLATION,
  MMU_PROHIBITS_STORE_VIOLATION,
  CALL_TRAP,
  RETURN_TRAP
} cheri_capability_exception_e;

//////////////////////////////////
// Control and status registers //
//////////////////////////////////

// CSR operations
typedef enum logic [1:0] {
  CSR_OP_READ,
  CSR_OP_WRITE,
  CSR_OP_SET,
  CSR_OP_CLEAR
} csr_op_e;

// Privileged mode
typedef enum logic[1:0] {
  PRIV_LVL_M = 2'b11,
  PRIV_LVL_H = 2'b10,
  PRIV_LVL_S = 2'b01,
  PRIV_LVL_U = 2'b00
} priv_lvl_e;

// Constants for the dcsr.xdebugver fields
typedef enum logic[3:0] {
   XDEBUGVER_NO     = 4'd0, // no external debug support
   XDEBUGVER_STD    = 4'd4, // external debug according to RISC-V debug spec
   XDEBUGVER_NONSTD = 4'd15 // debug not conforming to RISC-V debug spec
} x_debug_ver_e;


//////////////
// ID stage //
//////////////

// Operand a selection
typedef enum logic[1:0] {
  OP_A_REG_A,
  OP_A_FWD,
  OP_A_CURRPC,
  OP_A_IMM
} op_a_sel_e;

// CHERI Operand A selection
typedef enum logic [2:0] {
  CHERI_OP_A_REG_NUM,
  CHERI_OP_A_REG_CAP,
  CHERI_OP_A_REG_DDC,
  CHERI_OP_A_PCC,
  CHERI_OP_A_FWD
} c_op_a_sel_e;

// Immediate a selection
typedef enum logic {
  IMM_A_Z,
  IMM_A_ZERO
} imm_a_sel_e;

// Operand b selection
typedef enum logic {
  OP_B_REG_B,
  OP_B_IMM
} op_b_sel_e;

// CHERI Operand B selection
typedef enum logic [2:0] {
  CHERI_OP_B_REG_NUM,
  CHERI_OP_B_REG_CAP,
  CHERI_OP_B_REG_DDC,
  CHERI_OP_B_PCC,
  CHERI_OP_B_IMM
} c_op_b_sel_e;

// Immediate b selection
typedef enum logic [2:0] {
  IMM_B_I,
  IMM_B_S,
  IMM_B_B,
  IMM_B_U,
  IMM_B_J,
  IMM_B_INCR_PC,
  IMM_B_INCR_ADDR,
  IMM_B_ZERO
} imm_b_sel_e;

// CHERI Immediate B selection
typedef enum logic [2:0] {
  CHERI_IMM_B_I,
  CHERI_IMM_B_S,
  CHERI_IMM_B_U,
  CHERI_IMM_B_INCR_PC,
  CHERI_IMM_B_RS2
} cheri_imm_b_sel_e;

// Regfile write data selection
typedef enum logic [1:0] {
  RF_WD_LSU,
  RF_WD_EX,
  RF_WD_CSR,
  RF_WD_CHERI
} rf_wd_sel_e;

//////////////
// IF stage //
//////////////

// PC mux selection
typedef enum logic [2:0] {
  PC_BOOT,
  PC_JUMP,
  PC_EXC,
  PC_ERET,
  PC_DRET
} pc_sel_e;

// Exception PC mux selection
typedef enum logic [1:0] {
  EXC_PC_EXC,
  EXC_PC_IRQ,
  EXC_PC_DBD,
  EXC_PC_DBG_EXC // Exception while in debug mode
} exc_pc_sel_e;

// Exception cause
typedef enum logic [5:0] {
  EXC_CAUSE_INSN_ADDR_MISA     = 6'h00,
  EXC_CAUSE_ILLEGAL_INSN       = 6'h02,
  EXC_CAUSE_BREAKPOINT         = 6'h03,
  EXC_CAUSE_LOAD_ACCESS_FAULT  = 6'h05,
  EXC_CAUSE_STORE_ACCESS_FAULT = 6'h07,
  EXC_CAUSE_ECALL_MMODE        = 6'h0B
} exc_cause_e;

// Debug cause
typedef enum logic [2:0] {
  DBG_CAUSE_NONE    = 3'h0,
  DBG_CAUSE_EBREAK  = 3'h1,
  DBG_CAUSE_TRIGGER = 3'h2,
  DBG_CAUSE_HALTREQ = 3'h3,
  DBG_CAUSE_STEP    = 3'h4
} dbg_cause_e;

// CSRs
typedef enum logic[11:0] {
  // Machine information
  CSR_MHARTID   = 12'hF14,

  // Machine trap setup
  CSR_MSTATUS   = 12'h300,
  CSR_MISA      = 12'h301,
  CSR_MTVEC     = 12'h305,

  // Machine trap handling
  CSR_MSCRATCH  = 12'h340,
  CSR_MEPC      = 12'h341,
  CSR_MCAUSE    = 12'h342,
  CSR_MTVAL     = 12'h343,

  // Debug/trace
  CSR_DCSR      = 12'h7b0,
  CSR_DPC       = 12'h7b1,

  // Debug
  CSR_DSCRATCH0 = 12'h7b2, // optional
  CSR_DSCRATCH1 = 12'h7b3, // optional

  // CHERI CSRs
  CSR_UCCSR = 12'h8C0,
  CSR_SCCSR = 12'h9C0,
  CSR_MCCSR = 12'hBC0,

  // Machine Counter/Timers
  CSR_MCOUNTINHIBIT      = 12'h320,
  CSR_MCYCLE             = 12'hB00,
  CSR_MCYCLEH            = 12'hB80,
  CSR_MINSTRET           = 12'hB02,
  CSR_MINSTRETH          = 12'hB82
} csr_num_e;

// CHERI SCR
typedef enum logic [4:0] {
  SCR_PCC = 5'h00, // shouldn't necessarily be implemented same as the ones below
  SCR_DDC = 5'h01, // should always be accessible

  SCR_UTCC = 5'h04,
  SCR_UTDC = 5'h05,
  SCR_USCRATCHC = 5'h06,
  SCR_UEPCC = 5'h07,

  SCR_STCC = 5'h0C,
  SCR_STDC = 5'h0D,
  SCR_SSCRATCHC = 5'h0E,
  SCR_SEPCC = 5'h0F,

  SCR_MTCC = 5'h1C, // should always be accessible
  SCR_MTDC = 5'h1D,
  SCR_MSCRATCHC = 5'h1E,
  SCR_MEPCC = 5'h1F // should always be accessible
} scr_num_e;

// CHERI SCR operations
typedef enum logic [1:0] {
  SCR_NONE,
  SCR_WRITE,
  SCR_READ,
  SCR_READWRITE
} scr_op_e;

// CSR mhpmcounter-related offsets and mask
parameter logic [11:0] CSR_OFF_MCOUNTER_SETUP = 12'h320; // mcounter_setup @ 12'h323 - 12'h33F
parameter logic [11:0] CSR_OFF_MCOUNTER       = 12'hB00; // mcounter       @ 12'hB03 - 12'hB1F
parameter logic [11:0] CSR_OFF_MCOUNTERH      = 12'hB80; // mcounterh      @ 12'hB83 - 12'hB9F
parameter logic [11:0] CSR_MASK_MCOUNTER      = 12'hFE0;

endpackage
