/**
 * Avalon Wrapper for ibex core
 */

`define RFVI

module ibex_core_avalon #(
    parameter int unsigned MHPMCounterNum   = 0,
    parameter int unsigned MHPMCounterWidth = 40,
    parameter bit RV32E                     = 0,
    parameter bit RV32M                     = 1,
    parameter int unsigned DmHaltAddr       = 32'h1A110800,
    parameter int unsigned DmExceptionAddr  = 32'h1A110808
) (
    // Clock and Reset
    input  logic        clk_i,
    input  logic        rst_i,

    input  logic        test_en_i,     // enable all clock gates for testing

    // Core ID, Cluster ID and boot address are considered more or less static
    input  logic [ 3:0] core_id_i,
    input  logic [ 5:0] cluster_id_i,
    input  logic [31:0] boot_addr_i,

    // Instruction memory interface (Avalon)
    output logic [31:0] avm_instr_address,
    output logic        avm_instr_read,
    input  logic [31:0] avm_instr_readdata,
    input  logic        avm_instr_waitrequest,
    input  logic        avm_instr_readdatavalid,

    // Data memory interface (Avalon)
    output logic [31:0] avm_main_address,
    output logic [3:0]  avm_main_byteenable,
    output logic        avm_main_read,
    input  logic [31:0] avm_main_readdata,
    output logic        avm_main_write,
    output logic [31:0] avm_main_writedata,
    input  logic        avm_main_waitrequest,
    input  logic        avm_main_readdatavalid,
    input  logic [1:0]  avm_main_response,

    // Interrupt inputs
    input  logic        irq_i,                 // level sensitive IR lines
    input  logic [4:0]  irq_id_i,
    output logic        irq_ack_o,             // irq ack
    output logic [4:0]  irq_id_o,

    // Debug Interface
    input  logic        debug_req_i,

    // RISC-V Formal Interface
    // Does not comply with the coding standards of _i/_o suffixes, but follows
    // the convention of RISC-V Formal Interface Specification.
`ifdef RVFI
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [ 1:0] rvfi_mode,
    output logic [ 4:0] rvfi_rs1_addr,
    output logic [ 4:0] rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [ 4:0] rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [ 3:0] rvfi_mem_rmask,
    output logic [ 3:0] rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata,
`endif

`ifdef DII
    input logic [31:0]  dii_insn,
    input logic [15:0]  dii_time,
    input logic [7:0]   dii_cmd,
    output logic        dii_ready,
    input logic         dii_valid,
`endif

`ifdef DII
    output logic        perf_imiss_o,
`endif

    // CPU Control Signals
    input  logic        fetch_enable_i
);

`ifdef DII
    logic perf_imiss;
    assign perf_imiss_o = perf_imiss;
`endif

    // set up connections for ibex inputs
    logic         instr_rvalid_i;
    logic [31:0]  instr_addr_o;
    logic [31:0]  instr_rdata_i;
    logic         instr_req_o;
    logic         instr_gnt_i;

    logic         data_rvalid_i;
    logic [3:0]   data_be_o;
    logic [31:0]  data_addr_o;
    logic [31:0]  data_wdata_o;
    logic [31:0]  data_rdata_i;
    logic         data_err_i;
    logic         data_we_o;
    logic         data_req_o;
    logic         data_gnt_i;

    avalon_ibex_translator_main translator_main (
        .clock(clk_i),
        .reset_n(~rst_i),

        // inputs to translator
        .data_req_i(data_req_o),
        .data_we_i(data_we_o),
        .data_be_i(data_be_o),
        // our main memory interface is word-addressed but the ibex core is byte-addressed
        .data_addr_i({2'b0, data_addr_o[31:2]}),
        .data_wdata_i(data_wdata_o),
        
        .avm_main_waitrequest(avm_main_waitrequest),
        .avm_main_readdatavalid(avm_main_readdatavalid),
        .avm_main_readdata(avm_main_readdata),
        .avm_main_response(avm_main_response),

        // outputs from translator
        .data_gnt_o(data_gnt_i),
        .data_rvalid_o(data_rvalid_i),
        .data_rdata_o(data_rdata_i),
        .data_err_o(data_err_i),

        .avm_main_address(avm_main_address),
        .avm_main_byteenable(avm_main_byteenable),
        .avm_main_read(avm_main_read),
        .avm_main_write(avm_main_write),
        .avm_main_writedata(avm_main_writedata)
    );

    avalon_ibex_translator_instr translator_instr (
        .clock(clk_i),
        .reset_n(~rst_i),

        // inputs to translator
        .instr_req_i(instr_req_o),
        // our memory is word-addressed but the ibex core is byte-addressed
        .instr_addr_i({2'b0, instr_addr_o[31:2]}),

        .avm_instr_readdata(avm_instr_readdata),
        .avm_instr_waitrequest(avm_instr_waitrequest),
        .avm_instr_readdatavalid(avm_instr_readdatavalid),

        // outputs from translator
        .instr_gnt_o(instr_gnt_i),
        .instr_rvalid_o(instr_rvalid_i),
        .instr_rdata_o(instr_rdata_i),

        .avm_instr_read(avm_instr_read),
        .avm_instr_address(avm_instr_address)
    );



    ibex_core #(
        .MHPMCounterNum   (MHPMCounterNum),
        .MHPMCounterWidth (MHPMCounterWidth),
        .RV32E            (RV32E),
        .RV32M            (RV32M),
        .DmHaltAddr       (DmHaltAddr),
        .DmExceptionAddr  (DmExceptionAddr)
    ) u_core (
        // Clock and reset
        .clk_i          (clk_i),
        .rst_ni         (~rst_i),
        .test_en_i      (test_en_i),

        // Configuration
        .core_id_i      (core_id_i),
        .cluster_id_i   (cluster_id_i),
        .boot_addr_i    (boot_addr_i),

        // Instruction memory interface
        .instr_rvalid_i (instr_rvalid_i),
        .instr_addr_o   (instr_addr_o),
        .instr_rdata_i  (instr_rdata_i),
        .instr_req_o    (instr_req_o),
        .instr_gnt_i    (instr_gnt_i),



        // Data memory interface
        .data_rvalid_i  (data_rvalid_i),
        .data_be_o      (data_be_o),
        .data_addr_o    (data_addr_o),
        .data_wdata_o   (data_wdata_o),
        .data_rdata_i   (data_rdata_i),
        .data_err_i     (data_err_i),
        .data_we_o      (data_we_o),
        .data_req_o     (data_req_o),
        .data_gnt_i     (data_gnt_i),

        // Interrupt inputs
        .irq_i          (irq_i),
        .irq_id_i       (irq_id_i),
        .irq_ack_o      (irq_ack_o),
        .irq_id_o       (irq_id_o),

        // Debug interface
        .debug_req_i    (debug_req_i),
        
        // RISC-V Formal Interface
        // Does not comply with the coding standards of _i/_o suffixes, but follows
        // the convention of RISC-V Formal Interface Specification.
    `ifdef RVFI
        .rvfi_valid     (rvfi_valid),
        .rvfi_order     (rvfi_order),
        .rvfi_insn      (rvfi_insn),
        .rvfi_insn_uncompressed (),
        .rvfi_trap      (rvfi_trap),
        .rvfi_halt      (rvfi_halt),
        .rvfi_intr      (rvfi_intr),
        .rvfi_mode      (rvfi_mode),
        .rvfi_rs1_addr  (rvfi_rs1_addr),
        .rvfi_rs2_addr  (rvfi_rs2_addr),
        .rvfi_rs1_rdata (rvfi_rs1_rdata),
        .rvfi_rs2_rdata (rvfi_rs2_rdata),
        .rvfi_rd_addr   (rvfi_rd_addr),
        .rvfi_rd_wdata  (rvfi_rd_wdata),
        .rvfi_pc_rdata  (rvfi_pc_rdata),
        .rvfi_pc_wdata  (rvfi_pc_wdata),
        .rvfi_mem_addr  (rvfi_mem_addr),
        .rvfi_mem_rmask (rvfi_mem_rmask),
        .rvfi_mem_wmask (rvfi_mem_wmask),
        .rvfi_mem_rdata (rvfi_mem_rdata),
        .rvfi_mem_wdata (rvfi_mem_wdata),
    `endif

    `ifdef DII
        .perf_imiss_o   (perf_imiss),
    `endif

        // Special control signal
        .fetch_enable_i (fetch_enable_i)
    );

endmodule //ibexcore
