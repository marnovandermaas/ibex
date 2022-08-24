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
    input  logic [31:0] hart_id_i,
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
    input  logic        irq_software_i,
    input  logic        irq_timer_i,
    input  logic        irq_external_i,
    input  logic [14:0] irq_fast_i,
    input  logic        irq_nm_i,       // non-maskeable interrupt

    // Debug Interface
    input  logic        debug_req_i,

    // RISC-V Formal Interface
    // Does not comply with the coding standards of _i/_o suffixes, but follows
    // the convention of RISC-V Formal Interface Specification.
`ifdef RVFI
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic [31:0] rvfi_insn_uncompressed,
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
    output logic        perf_imiss_o,
`endif

    // CPU Control Signals
    input  logic        fetch_enable_i,
    output logic        core_sleep_o
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
    logic         instr_err_i;

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

    ibex_register_file_ff #(
      .RV32E            (RV32E)
    ) register_file_i (
      .clk_i (clk),
      .rst_ni(rst_ni),

      .test_en_i       (test_en_i),
      .dummy_instr_id_i(dummy_instr_id),

      .raddr_a_i(rf_raddr_a),
      .rdata_a_o(rf_rdata_a_ecc),
      .raddr_b_i(rf_raddr_b),
      .rdata_b_o(rf_rdata_b_ecc),
      .waddr_a_i(rf_waddr_wb),
      .wdata_a_i(rf_wdata_wb_ecc),
      .we_a_i   (rf_we_wb),
      .err_o    (rf_alert_major_internal)
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

        // Configuration
        .hart_id_i      (hart_id_i),
        .boot_addr_i    (boot_addr_i),

        // Instruction memory interface
        .instr_req_o    (instr_req_o),
        .instr_gnt_i    (instr_gnt_i),
        .instr_rvalid_i (instr_rvalid_i),
        .instr_addr_o   (instr_addr_o),
        .instr_rdata_i  (instr_rdata_i),
        .instr_err_i    (instr_err_i),

        // Data memory interface
        .data_req_o     (data_req_o),
        .data_gnt_i     (data_gnt_i),
        .data_rvalid_i  (data_rvalid_i),
        .data_we_o      (data_we_o),
        .data_be_o      (data_be_o),
        .data_addr_o    (data_addr_o),
        .data_wdata_o   (data_wdata_o),
        .data_rdata_i   (data_rdata_i),
        .data_err_i     (data_err_i),

        .dummy_instr_id_o (dummy_instr_id),
        .rf_raddr_a_o     (rf_raddr_a),
        .rf_raddr_b_o     (rf_raddr_b),
        .rf_waddr_wb_o    (rf_waddr_wb),
        .rf_we_wb_o       (rf_we_wb),
        .rf_wdata_wb_ecc_o(rf_wdata_wb_ecc),
        .rf_rdata_a_ecc_i (rf_rdata_a_ecc_buf),
        .rf_rdata_b_ecc_i (rf_rdata_b_ecc_buf),

        .ic_tag_req_o      (ic_tag_req),
        .ic_tag_write_o    (ic_tag_write),
        .ic_tag_addr_o     (ic_tag_addr),
        .ic_tag_wdata_o    (ic_tag_wdata),
        .ic_tag_rdata_i    (ic_tag_rdata),
        .ic_data_req_o     (ic_data_req),
        .ic_data_write_o   (ic_data_write),
        .ic_data_addr_o    (ic_data_addr),
        .ic_data_wdata_o   (ic_data_wdata),
        .ic_data_rdata_i   (ic_data_rdata),
        .ic_scr_key_valid_i(scramble_key_valid_q),

        // Interrupt inputs
        .irq_software_i (irq_software_i),
        .irq_timer_i    (irq_timer_i),
        .irq_external_i (irq_external_i),
        .irq_fast_i     (irq_fast_i),
        .irq_nm_i       (irq_nm_i),

        // Debug interface
        .debug_req_i        (debug_req_i),
        .crash_dump_o       (crash_dump_o),
        .double_fault_seen_o(double_fault_seen_o),

        // RISC-V Formal Interface
        // Does not comply with the coding standards of _i/_o suffixes, but follows
        // the convention of RISC-V Formal Interface Specification.
    `ifdef RVFI
        .rvfi_valid,
        .rvfi_order,
        .rvfi_insn,
        .rvfi_insn_uncompressed,
        .rvfi_trap,
        .rvfi_halt,
        .rvfi_intr,
        .rvfi_mode,
        .rvfi_ixl,
        .rvfi_rs1_addr,
        .rvfi_rs2_addr,
        .rvfi_rs3_addr,
        .rvfi_rs1_rdata,
        .rvfi_rs2_rdata,
        .rvfi_rs3_rdata,
        .rvfi_rd_addr
        .rvfi_rd_wdata,
        .rvfi_pc_rdata,
        .rvfi_pc_wdata,
        .rvfi_mem_addr,
        .rvfi_mem_rmask,
        .rvfi_mem_wmask,
        .rvfi_mem_rdata,
        .rvfi_mem_wdata,
        .rvfi_ext_mip,
        .rvfi_ext_nmi,
        .rvfi_ext_debug_req,
        .rvfi_ext_mcycle,
    `endif

        // Special control signal
        .fetch_enable_i        (fetch_enable_i),
        .alert_minor_o         (core_alert_minor),
        .alert_major_internal_o(core_alert_major_internal),
        .alert_major_bus_o     (core_alert_major_bus),
        .icache_inval_o        (icache_inval),
        .core_busy_o           (core_busy_d)
    );

endmodule //ibexcore
