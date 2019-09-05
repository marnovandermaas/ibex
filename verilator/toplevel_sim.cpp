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
#include <deque>
#include <pthread.h>

#define WORD_SIZE 4
#define MEM_BASE_BYTES 0xC0000000
#define MEM_BASE_WORDS MEM_BASE_BYTES/WORD_SIZE
#define MEM_SIZE_BYTES 0x18BCB0
#define MEM_SIZE_WORDS MEM_SIZE_BYTES/WORD_SIZE
#define SPECIAL_ADDR_BYTES 0xC01DF008
#define READ_POLL_ADDR_BYTES 0xC01DF018
#define READ_DATA_ADDR_BYTES 0xC01DF028


double main_time = 0;

double sc_time_stamp() {
    return main_time;
}

static pthread_t input_thread;
static pthread_mutex_t input_lock = PTHREAD_MUTEX_INITIALIZER;
static std::deque<uint8_t> input_buf;

static void *input_worker(void *data __attribute__((unused))) {
    int c;
    while ((c = std::cin.get()) != EOF) {
        pthread_mutex_lock(&input_lock);
        if (c == '!') {
            input_buf.push_back('\r');
        } else if (c != '\n') {
            input_buf.push_back(c);
        }
        pthread_mutex_unlock(&input_lock);
    }
    return NULL;
}


// This will open a socket on the hostname and port provided
// It will then try to receive RVFI-DII packets and put the instructions
// from them into the core and simulate it.
// The RVFI trace is then sent back
int main(int argc, char** argv, char** env) {
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
    // read in memory contents
    std::ifstream infile("file.bin");
    std::vector<uint8_t> memory(std::istreambuf_iterator<char>(infile), {});
    memory.reserve(MEM_SIZE_BYTES);
    pthread_create(&input_thread, NULL, input_worker, NULL);

    // set up initial core inputs
    top->clk_i = 0;
    top->rst_i = 1;
    top->fetch_enable_i = 1;
    top->test_en_i = 0;
    top->boot_addr_i = 0xC0000000;
    top->avm_main_waitrequest = 0;
    top->eval();

    top->avm_instr_readdatavalid = 0;
    top->avm_instr_waitrequest = 0;

    top->clk_i = 1;
    top->rst_i = 0;
    top->eval();

    top->clk_i = 0;
    top->rst_i = 0;
    top->eval();

    top->clk_i = 1;
    top->rst_i = 1;
    top->eval();

    top->clk_i = 0;
    top->rst_i = 1;
    top->eval();

    top->rst_i = 0;
    top->clk_i = 0;
    top->eval();

    top->clk_i = 1;
    top->eval();

    int counter = 0;
    while (1) {

            if (top->rvfi_valid) {
                counter++;
            }

            top->rst_i = 0;
            if (top->avm_instr_read) {
                if (top->avm_instr_address < MEM_BASE_BYTES || top->avm_instr_address > MEM_BASE_BYTES + MEM_SIZE_BYTES) {
                    std::cout << "tried to read an instruction out of bounds, address 0x"
                              << std::hex << top->avm_instr_address << std::endl;
                    top->avm_instr_readdata = 0x13;
                    top->avm_instr_readdatavalid = 1;
                    top->avm_instr_waitrequest = 0;
                } else {
                    uint64_t readdata = 0;
                    // get instruction from memory
                    readdata |= memory[top->avm_instr_address - MEM_BASE_BYTES]     <<  0;
                    readdata |= memory[top->avm_instr_address - MEM_BASE_BYTES + 1] <<  8;
                    readdata |= memory[top->avm_instr_address - MEM_BASE_BYTES + 2] << 16;
                    readdata |= memory[top->avm_instr_address - MEM_BASE_BYTES + 3] << 24;

                    // set core inputs appropriately
                    top->avm_instr_readdata = readdata;
                    top->avm_instr_readdatavalid = 1;
                    top->avm_instr_waitrequest = 0;
                }
            } else {
                top->avm_instr_readdatavalid = 0;
                top->avm_instr_waitrequest = 0;
            }


            // perform main memory read
            if (top->avm_main_read) {
                // get the address so we can manipulate it
                unsigned int address = top->avm_main_address;

                if (address == READ_POLL_ADDR_BYTES) {
                    pthread_mutex_lock(&input_lock);
                    top->avm_main_readdata = (uint64_t)(input_buf.size() > 0) << 40;
                    pthread_mutex_unlock(&input_lock);
                    top->avm_main_response = 0b00;
                    top->avm_main_readdatavalid = 1;
                } else if (address == READ_DATA_ADDR_BYTES) {
                    pthread_mutex_lock(&input_lock);
                    top->avm_main_readdata = (uint64_t)(input_buf.front()) << 40;
                    input_buf.pop_front();
                    pthread_mutex_unlock(&input_lock);
                    top->avm_main_response = 0b00;
                    top->avm_main_readdatavalid = 1;
                    std::cout << "writing character to core: " << std::hex << (top->avm_main_readdata>>40) << std::endl;
                } else

                // check address is in bounds
                if (address >= (MEM_BASE_BYTES + MEM_SIZE_BYTES) || address < MEM_BASE_BYTES) {
                    // the core tried to read from an address outside the specified range
                    // set the signals appropriately
                    top->avm_main_response = 0b11;
                    top->avm_main_readdata = 0xdeadbeefdeadbeef;
                    top->avm_main_readdatavalid = 1;
                    std::cout << "out of bounds memory read - address: 0x" << std::hex << address << std::endl;
                } else {
                    // the core tried to read from an address within the specified range
                    // we need to get the correct data from memory

                    // translate the address so it is between 0x0 and 0x00003fff
                    address -= MEM_BASE_BYTES;

                    // we want to start with the highest byte address for this word since our
                    // memory is little endian
                    address += 7;

                    // for each bit in the byteenable, check if we should get that byte from memory
                    // if not, set it to 0
                    uint64_t data = 0;
                    const int BPW = 7;
                    for (int i = 0; i <= BPW; i++) {
                        data <<= 8;
                        data |= ((top->avm_main_byteenable>>(BPW-i)) | 0x1) ? memory[address-i] : 0;
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
                unsigned int address = top->avm_main_address;

                if (address == SPECIAL_ADDR_BYTES || address == SPECIAL_ADDR_BYTES+8) {
                    std::cout << (char) (top->avm_main_writedata>>40) << std::flush;
                } else

                // check address is in bounds
                if (address >= (MEM_BASE_BYTES + MEM_SIZE_BYTES) || address < MEM_BASE_BYTES) {
                    // the core tried to write to an address outside the specified range
                    // set the signals appropriately
                    top->avm_main_response = 0b11;
                    top->avm_main_waitrequest = 0;
                    std::cout << "out of bounds memory write - address: 0x" << std::hex << address << std::endl;
                } else {
                    // the core tried to read from an address within the specified range

                    // translate the address so it is between 0x0 and 0x00003fff
                    address -= MEM_BASE_BYTES;

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



            //std::cout << "eval 1 start" << std::endl;
            top->clk_i = 1;
            top->eval();
            //std::cout << "eval 1 end" << std::endl;

            // tracing
            #if VM_TRACE
            trace_obj.dump(main_time);
            trace_obj.flush();
            main_time++;
            #endif


            //std::cout << "eval 2 start" << std::endl;
            top->clk_i = 0;
            top->eval();
            //std::cout << "eval 2 end" << std::endl;

            // tracing
            #if VM_TRACE
            trace_obj.dump(main_time);
            trace_obj.flush();
            #endif

            main_time++;

        }

    std::cout << "finished" << std::endl << std::flush;
    delete top;
    exit(0);
}


