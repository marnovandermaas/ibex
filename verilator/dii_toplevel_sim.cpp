#include "Vibex_core_avalon.h"
#include "verilated.h"
#if VM_TRACE
#include <verilated_vcd_c.h>
#endif
#include <fstream>
#include <iostream>
#include <iomanip>
#include <cstdint>
#include <vector>
#include <unistd.h>
#include "socket_packet_utils.h"
#include <stdlib.h>

#define MEM_BASE_BYTES 0x80000000
#define MEM_BASE_WORDS 0x20000000
#define MEM_SIZE_BYTES 0x10000
#define MEM_SIZE_WORDS 0x2000000/4


struct RVFI_DII_Execution_Packet {
    std::uint64_t rvfi_order : 64;      // [00 - 07] Instruction number:      INSTRET value after completion.
    std::uint64_t rvfi_pc_rdata : 64;   // [08 - 15] PC before instr:         PC for current instruction
    std::uint64_t rvfi_pc_wdata : 64;   // [16 - 23] PC after instr:          Following PC - either PC + 4 or jump/trap target.
    std::uint64_t rvfi_insn : 64;       // [24 - 31] Instruction word:        32-bit command value.
    std::uint64_t rvfi_rs1_data : 64;   // [32 - 39] Read register values:    Values as read from registers named
    std::uint64_t rvfi_rs2_data : 64;   // [40 - 47]                          above. Must be 0 if register ID is 0.
    std::uint64_t rvfi_rd_wdata : 64;   // [48 - 55] Write register value:    MUST be 0 if rd_ is 0.
    std::uint64_t rvfi_mem_addr : 64;   // [56 - 63] Memory access addr:      Points to byte address (aligned if define
                                        //                                      is set). *Should* be straightforward.
                                        //                                      0 if unused.
    std::uint64_t rvfi_mem_rdata : 64;  // [64 - 71] Read data:               Data read from mem_addr (i.e. before write)
    std::uint64_t rvfi_mem_wdata : 64;  // [72 - 79] Write data:              Data written to memory by this command.
    std::uint8_t rvfi_mem_rmask : 8;    // [80]      Read mask:               Indicates valid bytes read. 0 if unused.
    std::uint8_t rvfi_mem_wmask : 8;    // [81]      Write mask:              Indicates valid bytes written. 0 if unused.
    std::uint8_t rvfi_rs1_addr : 8;     // [82]      Read register addresses: Can be arbitrary when not used,
    std::uint8_t rvfi_rs2_addr : 8;     // [83]                          otherwise set as decoded.
    std::uint8_t rvfi_rd_addr : 8;      // [84]      Write register address:  MUST be 0 if not used.
    std::uint8_t rvfi_trap : 8;         // [85] Trap indicator:          Invalid decode, misaligned access or
                                        //                                      jump command to misaligned address.
    std::uint8_t rvfi_halt : 8;         // [86] Halt indicator:          Marks the last instruction retired 
                                        //                                      before halting execution.
    std::uint8_t rvfi_intr : 8;         // [87] Trap handler:            Set for first instruction in trap handler.     
};

struct RVFI_DII_Instruction_Packet {
    std::uint32_t dii_insn : 32;      // [0 - 3] Instruction word: 32-bit instruction or command. The lower 16-bits
                                      // may decode to a 16-bit compressed instruction.
    std::uint16_t dii_time : 16;      // [5 - 4] Time to inject token.  The difference between this and the previous
                                      // instruction time gives a delay before injecting this instruction.
                                      // This can be ignored for models but gives repeatability for implementations
                                      // while shortening counterexamples.
    std::uint8_t dii_cmd : 8;         // [6] This token is a trace command.  For example, reset device under test.
    std::uint8_t padding : 8;         // [7]
};

double main_time = 0;

double sc_time_stamp() {
    return main_time;
}

RVFI_DII_Execution_Packet readRVFI(Vibex_core_avalon *top, bool signExtend);
void sendReturnTrace(std::vector<RVFI_DII_Execution_Packet> &returnTrace, unsigned long long socket);

// This will open a socket on the hostname and port provided
// It will then try to receive RVFI-DII packets and put the instructions
// from them into the core and simulate it.
// The RVFI trace is then sent back
int main(int argc, char** argv, char** env) {

    if (argc != 3) {
        std::cerr << "wrong number of args" << std::endl;
        exit(-1);
    }

    Verilated::commandArgs(argc, argv);
    Vibex_core_avalon* top = new Vibex_core_avalon;

    // set up tracing
    #if VM_TRACE
    Verilated::traceEverOn(true);
    VerilatedVcdC trace_obj;
    top->trace(&trace_obj, 99);
    trace_obj.open("vlt_d.vcd");
    #endif

    // initialise memory
    uint8_t *memory = (uint8_t *) malloc(MEM_SIZE_BYTES);
    if (memory == NULL) {
        std::cout << "memory is null" << std::endl;
    }

    // initialize the socket with the input parameters
    unsigned long long socket = serv_socket_create(argv[1], std::atoi(argv[2]));
    serv_socket_init(socket);

    // set up initial core inputs
    top->clk_i = 0;
    top->rst_i = 1;
    top->fetch_enable_i = 1;
    top->test_en_i = 0;
    top->boot_addr_i = 0x80000000;
    top->avm_main_waitrequest = 0;
    top->eval();

    top->avm_instr_readdatavalid = 0;
    top->avm_instr_waitrequest = 0;

    top->rst_i = 0;

    top->eval();

    int received = 0;
    int in_count = 0;
    int out_count = 0;

    char recbuf[sizeof(RVFI_DII_Instruction_Packet) + 1] = {0};
    std::vector<RVFI_DII_Instruction_Packet> instructions;
    std::vector<RVFI_DII_Execution_Packet> returntrace;
    while (1) {
        // send back execution trace if the number of instructions that have come out is equal to the
        // number that have gone in
        if (returntrace.size() > 0 && in_count == out_count) {
            sendReturnTrace(returntrace, socket);
        }


        RVFI_DII_Instruction_Packet *packet;
        while (in_count >= received) {
            // try to receive a packet

                serv_socket_getN((unsigned int *) recbuf, socket, sizeof(RVFI_DII_Instruction_Packet));

                // the last byte received will be 0 if our attempt to receive a packet was successful
                if (recbuf[8] == 0) {
                    packet = (RVFI_DII_Instruction_Packet *) recbuf;

                    instructions.push_back(*packet);
                    received++;
                    break;
                }

                // sleep for 0.1ms before trying to receive another instruction
                usleep(100);
        }

        // need to clock the core while there are still instructions in the buffer
        if ((in_count <= received) && received > 0 && ((in_count - out_count > 0) || in_count == 0 || (out_count == in_count && received > in_count))) {
            // read rvfi data and add packet to list of packets to send
            // the condition to read data here is that there is an rvfi valid signal
            // this deals with counting instructions that the core has finished executing
            if (in_count - out_count > 0 && top->rvfi_valid) {
                RVFI_DII_Execution_Packet execpacket = readRVFI(top, false);

                returntrace.push_back(execpacket);

                out_count++;
            }

            // detect imiss in order to replay instructions so they don't get lost
            if (top->perf_imiss_o && in_count > out_count) {
                // this will need to be reworked
                // currently, in order for this to work we need to remove illegal_insn from the assignment
                // to rvfi_trap since when the core is first started the instruction data is garbage so
                // this is high
                if (top->rvfi_valid && top->rvfi_trap) {
                    // if there has been a trap, then we know that we just tried to do a load/store
                    // we need to go back to out_count
                    // CHERI USES THE TRAP SIGNAL A LOT BUT ITS TRAPS TAKE FEWER CYCLES TO RECOVER FROM
                    //in_count = out_count + ((top->rvfi_insn & 0x0000007f) == 0x0000005b ? 1 : 0);
                    in_count = out_count + (((top->rvfi_insn & 0x0000007f) == 0x0000005b)
                                           && ((top->rvfi_insn & 0xfff07000) != 0xfec00000) ? 0 : 0);
                } else {
                    if (!instructions[out_count].dii_cmd) {
                        // the last instruction we saw coming out was a reset
                        // this means that we tried to do a jump straight away, and it will only come out of
                        // the rvfi signals later. we need to go forward 2 places from the out_cout
                        // (the jump has already been performed, so we want the instruction after it)
                        in_count = out_count + 2;
                    } else {
                        // the last instruction was an actual instruction. we are doing a jump but it hasn't
                        // come out of the rvfi signals yet so we need to skip it when replaying instructions
                        in_count = out_count + 1;
                    }
                }
            }

            // perform instruction read
            // returns instructions from the DII input from TestRIG
            top->avm_instr_readdata = instructions[in_count].dii_insn;
            top->rst_i = 0;
            if (instructions[in_count].dii_cmd) {
                if (top->avm_instr_read) {
                    // if we have instructions to feed into it, then set readdatavalid and waitrequest accordingly
                    if (received > in_count) {
                        top->avm_instr_readdatavalid = 1;
                        top->avm_instr_waitrequest = 0;
                        in_count++;
                        top->boot_addr_i = 0x00000000;
                    } else {
                        top->avm_instr_readdatavalid = 0;
                        top->avm_instr_waitrequest = 1;
                    }
                } else {
                    top->avm_instr_readdatavalid = 0;
                    top->avm_instr_waitrequest = 0;
                }
            } else {
                if (in_count - out_count == 0 && in_count < received) {
                top->avm_instr_readdatavalid = 0;
                    top->boot_addr_i = 0x80000000;
                    top->rst_i = 1;

                    // clear memory
                    for (int i = 0; i < MEM_SIZE_BYTES; i++) {
                        memory[i] = 0;
                    }

                    std::cout << "reset" << std::endl;

                    in_count++;
                }
            }


            // read rvfi data and add packet to list of packets to send
            // the condition to read data here is that the core has just been reset
            // this deals with counting reset instruction packets from TestRIG
            if (in_count - out_count > 0 && top->rst_i) {
                RVFI_DII_Execution_Packet execpacket = readRVFI(top, false);

                returntrace.push_back(execpacket);

                out_count++;
            }

            // perform main memory read
            if (top->avm_main_read) {
                // get the address so we can manipulate it
                int address = top->avm_main_address;

                // TestRIG specifies that byte addresses must be between 0x80000000 and 0x80008000
                // our avalon wrapper divides the byte address by 4 in order to get a word address
                // so we need to check for addresses between 0x20003fff and 0x20000000
                if (address >= (MEM_BASE_BYTES + MEM_SIZE_BYTES) || address < MEM_BASE_BYTES) {
                    // the core tried to read from an address outside the specified range
                    // set the signals appropriately
                    top->avm_main_response = 0b11;
                    top->avm_main_readdata = 0xdeadbeefdeadbeef;
                    top->avm_main_readdatavalid = 1;
                    std::cout << "out of bounds memory access - address: 0x" << std::hex << address << std::endl;
                } else {
                    // the core tried to read from an address within the specified range
                    // we need to get the correct data from memory

                    // translate the address so it is between 0x0 and 0x00003fff
                    address = address - MEM_BASE_BYTES;

                    // we want to start with the highest byte address for this word since our
                    // memory is little endian
                    address += 7;

                    // for each bit in the byteenable, check if we should get that byte from memory
                    // if not, set it to 0
                    unsigned long long data = 0;
                    // TODO clean this up into a for loop
                    const int BPW = 7;
                    for (int i = 0; i <= BPW; i++) {
                        data <<= 8;
                        data |= ((top->avm_main_byteenable>>(BPW-i)) & 0x1) ? memory[address-i] : 0;
                    }

                    // set the signals appropriately
                    top->avm_main_readdata = data;
                    top->avm_main_readdatavalid = 1;
                    top->avm_main_response = 0b00;
                }
            }

            // perform main memory writes
            if (top->avm_main_write) {
                // get the address so we can manipulate it
                int address = top->avm_main_address;


                // TestRIG specifies that byte addresses must be between 0x80000000 and 0x80008000
                // our avalon wrapper divides the byte address by 4 in order to get a word address
                // so we need to check for addresses between 0x20003fff and 0x20000000
                if (address >= (MEM_BASE_BYTES + MEM_SIZE_BYTES) || address < MEM_BASE_BYTES) {
                    // the core tried to write to an address outside the specified range
                    // set the signals appropriately
                    top->avm_main_response = 0b11;
                    top->avm_main_waitrequest = 0;
                    std::cout << "out of bounds memory access - address: 0x" << std::hex << address << std::endl;
                } else {
                    // the core tried to read from an address within the specified range

                    // translate the address so it is between 0x0 and 0x00003fff
                    address = address & 0x01ffffff;

                    // get the data from the core
                    uint64_t data = top->avm_main_writedata;

                    // we want to only change the memory values for which byteenable is high
                    // if byteenable is low, preserve that byte in memory
                    const int BPW = 8;
                    for (int i = 0; i < BPW; i++) {
                        memory[address + i] = (top->avm_main_byteenable>>i & 0x1) ? data : memory[address + i];
                        data >>= 8;
                    }

                    // set output signals appropriately
                    top->avm_main_response = 0b00;
                    top->avm_main_waitrequest = 0;
                }
            }


            if (!top->avm_main_write && !top->avm_main_read) {
                top->avm_main_readdatavalid = 0;
            }



            top->clk_i = 1;
            top->eval();

            // tracing
            #if VM_TRACE
            trace_obj.dump(main_time);
            trace_obj.flush();
            main_time++;
            #endif


            top->clk_i = 0;
            top->eval();

            // tracing
            #if VM_TRACE
            trace_obj.dump(main_time);
            trace_obj.flush();
            #endif

            main_time++;

            // if we have a large difference between the number of instructions that have gone in
            // and the number that have come out, something's gone wrong; exit the program
            if (in_count - out_count > 10) {
                break;
            }
        }

    }

    std::cout << "finished" << std::endl << std::flush;
    delete top;
    exit(0);
}

// send the return trace that is passed in over the socket that is passed in
void sendReturnTrace(std::vector<RVFI_DII_Execution_Packet> &returntrace, unsigned long long socket) {
    const int BULK_SEND = 50;

    if (returntrace.size() > 0) {
        int tosend = 1;
        for (int i = 0; i < returntrace.size(); i+=tosend) {
            tosend = 1;
            RVFI_DII_Execution_Packet sendarr[BULK_SEND];
            sendarr[0] = returntrace[i];

            // bulk send if possible
            if (returntrace.size() - i > BULK_SEND) {
                tosend = BULK_SEND;
                for (int j = 0; j < tosend; j++) {
                    sendarr[j] = returntrace[i+j];
                }
            }

            // loop to make sure that the packet has been properly sent
            while (
                !serv_socket_putN(socket, sizeof(RVFI_DII_Execution_Packet) * tosend, (unsigned int *) sendarr)
            ) {
                // empty
            }
        }
        returntrace.clear();
    }
}

RVFI_DII_Execution_Packet readRVFI(Vibex_core_avalon *top, bool signExtend) {
    unsigned long long signExtension;
    if (signExtend) {
        signExtension = 0xFFFFFFFF00000000;
    } else {
        signExtension = 0x0000000000000000;
    }

    RVFI_DII_Execution_Packet execpacket = {
        .rvfi_order = top->rvfi_order,
        .rvfi_pc_rdata = top->rvfi_pc_rdata     | ((top->rvfi_pc_rdata & 0x80000000) ? signExtension : 0),
        .rvfi_pc_wdata = top->rvfi_pc_wdata     | ((top->rvfi_pc_wdata & 0x80000000) ? signExtension : 0),
        .rvfi_insn = top->rvfi_insn             | ((top->rvfi_insn & 0x80000000) ? signExtension : 0 ),
        .rvfi_rs1_data = top->rvfi_rs1_rdata    | ((top->rvfi_rs1_rdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_rs2_data = top->rvfi_rs2_rdata    | ((top->rvfi_rs2_rdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_rd_wdata = top->rvfi_rd_wdata     | ((top->rvfi_rd_wdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_addr = top->rvfi_mem_addr     | ((top->rvfi_mem_addr & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_rdata = top->rvfi_mem_rdata   | ((top->rvfi_mem_rdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_wdata = top->rvfi_mem_wdata   | ((top->rvfi_mem_wdata & 0x80000000) ? signExtension : 0 ),
        .rvfi_mem_rmask = top->rvfi_mem_rmask,
        .rvfi_mem_wmask = top->rvfi_mem_wmask,
        .rvfi_rs1_addr = top->rvfi_rs1_addr,
        .rvfi_rs2_addr = top->rvfi_rs2_addr,
        .rvfi_rd_addr = top->rvfi_rd_addr,
        .rvfi_trap = top->rvfi_trap,
        .rvfi_halt = top->rst_i,
        .rvfi_intr = top->rvfi_intr
    };

    return execpacket;
}




