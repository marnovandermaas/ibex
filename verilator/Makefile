
LOCALINCLUDES=-I../rtl
FILELIST=../rtl/avalon/ibex_core_avalon.sv \
			../examples/sim/rtl/prim_clock_gating.sv \
			../rtl/ibex_defines.sv \
			../rtl/avalon/avalon_ibex_translator.sv \
			../rtl/ibex_alu.sv \
			../rtl/ibex_compressed_decoder.sv \
			../rtl/ibex_controller.sv \
			../rtl/ibex_core.sv \
			../rtl/ibex_cs_registers.sv \
			../rtl/ibex_decoder.sv \
			../rtl/ibex_ex_block.sv \
			../rtl/ibex_fetch_fifo.sv \
			../rtl/ibex_id_stage.sv \
			../rtl/ibex_if_stage.sv \
			../rtl/ibex_int_controller.sv \
			../rtl/ibex_load_store_unit.sv \
			../rtl/ibex_multdiv_fast.sv \
			../rtl/ibex_multdiv_slow.sv \
			../rtl/ibex_prefetch_buffer.sv \
			../rtl/ibex_register_file_ff.sv \
			../rtl/ibex_tracer_defines.sv \
			../rtl/ibex_tracer.sv

TARGET=ibex_core_avalon
SIMFILE=dii_toplevel_sim.cpp
LIBS=socket_packet_utils.c
VERILATOR_INCLUDE=/usr/local/share/verilator/include

default: all

all: verilator compile
trace: verilator-trace compile

verilator:
	verilator +define+RVFI +define+DII -Wno-WIDTH -Wno-UNOPTFLAT --cc $(FILELIST) --exe $(SIMFILE) $(LIBS)

verilator-trace:
	verilator +define+RVFI +define+DII -DTRACE -Wno-WIDTH -Wno-UNOPTFLAT --trace --cc $(FILELIST) --exe $(SIMFILE) $(LIBS)

compile:
	make -j -C obj_dir -f V$(TARGET).mk V$(TARGET)

clean:
	$(RM) -r obj_dir
