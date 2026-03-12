// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "processor.h"

#ifdef AXI_BUS
#include "VVortex_axi.h"
typedef VVortex_axi Device;
#else
#include "VVortex.h"
typedef VVortex Device;
#endif

#ifdef VCD_OUTPUT
#include <verilated_vcd_c.h>
#endif

#include <iostream>
#include <fstream>
#include <iomanip>
#include <mem.h>

#include <VX_config.h>
#include <ostream>
#include <list>
#include <queue>
#include <vector>
#include <sstream>
#include <unordered_map>

#include <dram_sim.h>
#include <util.h>

#ifndef MEMORY_BANKS
  #ifdef PLATFORM_PARAM_LOCAL_MEMORY_BANKS
    #define MEMORY_BANKS PLATFORM_PARAM_LOCAL_MEMORY_BANKS
  #else
    #define MEMORY_BANKS 2
  #endif
#endif

#ifndef MEM_CLOCK_RATIO
#define MEM_CLOCK_RATIO 1
#endif

#ifndef TRACE_START_TIME
#define TRACE_START_TIME 0ull
#endif

#ifndef TRACE_STOP_TIME
#define TRACE_STOP_TIME -1ull
#endif

#ifndef VERILATOR_RESET_VALUE
#define VERILATOR_RESET_VALUE 2
#endif

#if (XLEN == 32)
typedef uint32_t Word;
#elif (XLEN == 64)
typedef uint64_t Word;
#else
#error unsupported XLEN
#endif

#define VL_WDATA_GETW(lwp, i, n, w) \
  VL_SEL_IWII(0, n * w, 0, 0, lwp, i * w, w)

using namespace vortex;

static uint64_t timestamp = 0;

double sc_time_stamp() {
  return timestamp;
}

///////////////////////////////////////////////////////////////////////////////

static bool trace_enabled = false;
static uint64_t trace_start_time = TRACE_START_TIME;
static uint64_t trace_stop_time  = TRACE_STOP_TIME;

bool sim_trace_enabled() {
  if (timestamp >= trace_start_time
   && timestamp < trace_stop_time)
    return true;
  return trace_enabled;
}

void sim_trace_enable(bool enable) {
  trace_enabled = enable;
}

///////////////////////////////////////////////////////////////////////////////

class Processor::Impl {
public:
  Impl() : dram_sim_(MEM_CLOCK_RATIO) {
    // force random values for unitialized signals
    Verilated::randReset(VERILATOR_RESET_VALUE);
    Verilated::randSeed(50);

    // turn off assertion before reset
    Verilated::assertOn(false);
    // device_ 、ram_ 、 tfp_等成员变量都是在private中声明的，在Impl的构造函数中进行初始化
    // create RTL module instance  
    device_ = new Device();

  #ifdef VCD_OUTPUT
    Verilated::traceEverOn(true);
    tfp_ = new VerilatedVcdC();
    device_->trace(tfp_, 99);
    tfp_->open("trace.vcd");
  #endif

    ram_ = nullptr;

  #ifndef NDEBUG
    // dump device configuration
    std::cout << "CONFIGS:"
              << " num_threads=" << NUM_THREADS
              << ", num_warps=" << NUM_WARPS
              << ", num_cores=" << NUM_CORES
              << ", num_clusters=" << NUM_CLUSTERS
              << ", socket_size=" << SOCKET_SIZE
              << ", local_mem_base=0x" << std::hex << LMEM_BASE_ADDR << std::dec
              << ", num_barriers=" << NUM_BARRIERS
              << std::endl;
  #endif
    // reset the device
    this->reset();

    // Turn on assertion after reset
    Verilated::assertOn(true);
  }

  ~Impl() {
    this->cout_flush();

  #ifdef VCD_OUTPUT
    tfp_->close();
    delete tfp_;
  #endif

    delete device_;
  }
  
  // cout_flush函数用于将print_bufs_中的内容打印到控制台，并在打印完成后清空缓冲区
  // 成员定义部分可知，print_bufs_是一个unordered_map，键为uint32_t类型，值为stringstream类型。
  // key部分是对应vortex组件中每个core的id，value部分是一个stringstream对象，用于存储该core的输出内容。
  void cout_flush() {
    for (auto& buf : print_bufs_) {
      auto str = buf.second.str();
      if (!str.empty()) {
        std::cout << "#" << buf.first << ": " << str << std::endl;
      }
    }
  }
  
  // attach_ram函数用于将RAM实例与Processor实例关联起来，
  // Impl类中的attach_ram函数将传入的RAM指针保存在Impl实例的成员变量ram_中，以便在后续的内存访问中使用
  void attach_ram(RAM* ram) {
    ram_ = ram;
  }

  void run() {

  #ifndef NDEBUG
    std::cout << std::dec << timestamp << ": [sim] run()" << std::endl;
  #endif

    // start execution
    running_ = true;
    device_->reset = 0;   // 高电平复位，低电平运行

    // wait on device to go busy，即等待处理器开始执行程序
    while (!device_->busy) {
      this->tick();
    }

    // wait on device to go idle，即等待处理器执行完程序
    while (device_->busy) {
      this->tick();
    }

    // reset device
    this->reset();
    // 程序执行结束，打印输出缓冲区中的内容，并刷新到控制台
    this->cout_flush();
  }

  void dcr_write(uint32_t addr, uint32_t value) {
    device_->dcr_wr_valid = 1;
    device_->dcr_wr_addr  = addr;
    device_->dcr_wr_data  = value;
    while (device_->dcr_wr_valid) {   // valid信号由dcr_bus_eval函数在每个时钟周期结束时清除
      this->tick();
    }
  }

private:

  void reset() {
    running_ = false;

    print_bufs_.clear();

    pending_mem_reqs_.clear();

    {
      std::queue<mem_req_t*> empty;
      std::swap(dram_queue_, empty);
    }

    mem_rd_rsp_active_ = false;
    mem_wr_rsp_active_ = false;

    this->mem_bus_reset();

    this->dcr_bus_reset();

    device_->reset = 1;

    for (int i = 0; i < RESET_DELAY; ++i) {
      device_->clk = 0;
      this->eval();
      device_->clk = 1;
      this->eval();
    }
  }

  void tick() {

    device_->clk = 0;
    // eval()函数会调用device_->eval()，这是Verilator生成的函数，用于评估RTL模块的状态，是vortex组件。
    // 此外：在每个上升沿和下降沿，都会调用mem_bus_eval()和dcr_bus_eval()函数，以处理内存总线和DCR总线上的请求和响应。
    this->eval();   

    this->mem_bus_eval(0);  
    this->dcr_bus_eval(0);

    device_->clk = 1;
    this->eval();

    this->mem_bus_eval(1);
    this->dcr_bus_eval(1);
    // DRAM模拟器的时钟节拍，在每个时钟周期结束时调用dram_sim_.tick()，以更新DRAM模拟器的状态并处理任何待处理的内存请求
    dram_sim_.tick();
    // 后面再看； 学习Lambda表达式和回调函数的用法； 这里的lambda表达式作为回调函数传递给dram_sim_.send_request()，当DRAM模拟器完成内存请求的处理后，会调用这个回调函数来通知Processor实例。
    if (!dram_queue_.empty()) {
      auto mem_req = dram_queue_.front();
      if (dram_sim_.send_request(mem_req->write, mem_req->addr, 0, [](void* arg) {
        // 将传入的void*指针转换回mem_req_t*类型，以便在回调函数中访问内存请求的相关信息。
        auto orig_req = reinterpret_cast<mem_req_t*>(arg);  
        // 写事务：ready早就设置为true了，回调函数直接删除请求对象；
        // 读事务：ready初始为false，等数据准备好后由回调函数设置为true，等待mem_bus_eval函数在下一个时钟周期检测到ready=true后，发送读响应并删除请求对象。
        if (orig_req->ready) {
          delete orig_req;      
        } else {
          orig_req->ready = true;
        }
      }, mem_req)) {
        dram_queue_.pop();
      }
    }

  #ifndef NDEBUG
    fflush(stdout);
  #endif
  }

  void eval() {
    device_->eval();
  #ifdef VCD_OUTPUT
    if (sim_trace_enabled()) {
      tfp_->dump(timestamp);
    } else {
      exit(-1);
    }
  #endif
    ++timestamp;
  }

#ifdef AXI_BUS

  void mem_bus_reset() {
    device_->m_axi_wready[0]  = 0;
    device_->m_axi_awready[0] = 0;
    device_->m_axi_arready[0] = 0;
    device_->m_axi_rvalid[0]  = 0;
    device_->m_axi_bvalid[0]  = 0;
  }

  void mem_bus_eval(bool clk) {
    if (!clk) {
      mem_rd_rsp_ready_ = device_->m_axi_rready[0];
      mem_wr_rsp_ready_ = device_->m_axi_bready[0];
      return;
    }

    if (ram_ == nullptr) {
      device_->m_axi_wready[0]  = 0;
      device_->m_axi_awready[0] = 0;
      device_->m_axi_arready[0] = 0;
      return;
    }

    // process memory read responses
    if (mem_rd_rsp_active_
     && device_->m_axi_rvalid[0] && mem_rd_rsp_ready_) {
      mem_rd_rsp_active_ = false;
    }
    if (!mem_rd_rsp_active_) {
      if (!pending_mem_reqs_.empty()
       && (*pending_mem_reqs_.begin())->ready
       && !(*pending_mem_reqs_.begin())->write) {
        auto mem_rsp_it = pending_mem_reqs_.begin();
        auto mem_rsp = *mem_rsp_it;
        /*
        printf("%0ld: [sim] MEM Rd Rsp: addr=0x%0lx, data=0x", timestamp, mem_rsp->addr);
        for (int i = MEM_BLOCK_SIZE-1; i >= 0; --i) {
          printf("%02x", mem_rsp->block[i]);
        }
        printf("\n");
        */
        device_->m_axi_rvalid[0] = 1;
        device_->m_axi_rid[0]    = mem_rsp->tag;
        device_->m_axi_rresp[0]  = 0;
        device_->m_axi_rlast[0]  = 1;
        memcpy(device_->m_axi_rdata[0].data(), mem_rsp->block.data(), MEM_BLOCK_SIZE);
        pending_mem_reqs_.erase(mem_rsp_it);
        mem_rd_rsp_active_ = true;
        delete mem_rsp;
      } else {
        device_->m_axi_rvalid[0] = 0;
      }
    }

    // process memory write responses
    if (mem_wr_rsp_active_
     && device_->m_axi_bvalid[0] && mem_wr_rsp_ready_) {
      mem_wr_rsp_active_ = false;
    }
    if (!mem_wr_rsp_active_) {
      if (!pending_mem_reqs_.empty()
       && (*pending_mem_reqs_.begin())->ready
       && (*pending_mem_reqs_.begin())->write) {
        auto mem_rsp_it = pending_mem_reqs_.begin();
        auto mem_rsp = *mem_rsp_it;
        /*
         printf("%0ld: [sim] MEM Wr Rsp: addr=0x%0lx\n", timestamp, mem_rsp->addr);
        */
        device_->m_axi_bvalid[0] = 1;
        device_->m_axi_bid[0]    = mem_rsp->tag;
        device_->m_axi_bresp[0]  = 0;
        pending_mem_reqs_.erase(mem_rsp_it);
        mem_wr_rsp_active_ = true;
        delete mem_rsp;
      } else {
        device_->m_axi_bvalid[0] = 0;
      }
    }

    // select the memory bank
    uint32_t req_addr = device_->m_axi_wvalid[0] ? device_->m_axi_awaddr[0] : device_->m_axi_araddr[0];

    // process memory requests
    if ((device_->m_axi_wvalid[0] || device_->m_axi_arvalid[0]) && running_) {
      if (device_->m_axi_wvalid[0]) {
        auto byteen = device_->m_axi_wstrb[0];
        auto base_addr = device_->m_axi_awaddr[0];
        auto data = (uint8_t*)device_->m_axi_wdata[0].data();

        if (base_addr >= uint64_t(IO_COUT_ADDR)
         && base_addr < (uint64_t(IO_COUT_ADDR) + IO_COUT_SIZE)) {
          // process console output
          for (int i = 0; i < MEM_BLOCK_SIZE; i++) {
            if ((byteen >> i) & 0x1) {
              auto& ss_buf = print_bufs_[i];
              char c = data[i];
              ss_buf << c;
              if (c == '\n') {
                std::cout << std::dec << "#" << i << ": " << ss_buf.str() << std::flush;
                ss_buf.str("");
              }
            }
          }
        } else {
          // process writes
          /*
          printf("%0ld: [sim] MEM Wr: addr=0x%0lx, byteen=0x", timestamp, base_addr);
          for (int i = (MEM_BLOCK_SIZE/4)-1; i >= 0; --i) {
            printf("%x", (int)((byteen >> (4 * i)) & 0xf));
          }
          printf(", data=0x");
          for (int i = MEM_BLOCK_SIZE-1; i >= 0; --i) {
            printf("%02x", data[i]);
          }
          printf("\n");
          */
          for (int i = 0; i < MEM_BLOCK_SIZE; i++) {
            if ((byteen >> i) & 0x1) {
              (*ram_)[base_addr + i] = data[i];
            }
          }

          auto mem_req = new mem_req_t();
          mem_req->tag   = device_->m_axi_awid[0];
          mem_req->addr  = device_->m_axi_awaddr[0];
          mem_req->write = true;
          mem_req->ready = false;
          pending_mem_reqs_.emplace_back(mem_req);

          // send dram request
          dram_queue_.push(mem_req);
        }
      } else {
        // process reads
        auto mem_req = new mem_req_t();
        mem_req->tag  = device_->m_axi_arid[0];
        mem_req->addr = device_->m_axi_araddr[0];
        ram_->read(mem_req->block.data(), device_->m_axi_araddr[0], MEM_BLOCK_SIZE);
        mem_req->write = false;
        mem_req->ready = false;
        pending_mem_reqs_.emplace_back(mem_req);

        // send dram request
        dram_queue_.push(mem_req);
      }
    }

    device_->m_axi_wready[0]  = running_;
    device_->m_axi_awready[0] = running_;
    device_->m_axi_arready[0] = running_;
  }

#else

  void mem_bus_reset() {
    device_->mem_req_ready = 0;
    device_->mem_rsp_valid = 0;
  }
  // device <--> impl <--> RAM
  void mem_bus_eval(bool clk) {
    // 下降沿采样ready,
    if (!clk) {
      mem_rd_rsp_ready_ = device_->mem_rsp_ready;
      return;
    }
    // 如果没有连接RAM，mem_req_ready信号保持为0，表示处理器无法接受内存请求
    if (ram_ == nullptr) {
      device_->mem_req_ready = 0;
      return;
    }

    // process memory read responses    (mem -> device)
    // 1. 等待完成逻辑，等上次传输完成，清除active标志。
    if (mem_rd_rsp_active_
    && device_->mem_rsp_valid && mem_rd_rsp_ready_) {
      mem_rd_rsp_active_ = false;         
    }
    // 2. 总线空闲时逻辑
    if (!mem_rd_rsp_active_) {
      // 检查 pending 队列里有没有已经准备好（ready=true）的读请求
      if (!pending_mem_reqs_.empty()
       && (*pending_mem_reqs_.begin())->ready) {
        // 3. 填数据，相关控制信号和数据信号 填到 总线信号线上。
        device_->mem_rsp_valid = 1; 
        auto mem_rsp_it = pending_mem_reqs_.begin();
        auto mem_rsp = *mem_rsp_it;
        /*
        printf("%0ld: [sim] MEM Rd Rsp: tag=0x%0lx, addr=0x%0lx, data=0x", timestamp, mem_rsp->tag, mem_rsp->addr);
        for (int i = MEM_BLOCK_SIZE-1; i >= 0; --i) {
          printf("%02x", mem_rsp->block[i]);
        }
        printf("\n");
        */
        memcpy(VDataCast<void*, MEM_BLOCK_SIZE>::get(device_->mem_rsp_data), mem_rsp->block.data(), MEM_BLOCK_SIZE);
        device_->mem_rsp_tag = mem_rsp->tag;
        // 4. 清理队列，设置active，删除已处理的内存请求对象
        pending_mem_reqs_.erase(mem_rsp_it);
        mem_rd_rsp_active_ = true;   
        delete mem_rsp;
      } else {
        device_->mem_rsp_valid = 0;   
      }
    }

    // process memory requests     (device -> mem)
    if (device_->mem_req_valid && running_) {
      uint64_t byte_addr = (device_->mem_req_addr * MEM_BLOCK_SIZE);
      // 1. 写操作：
      if (device_->mem_req_rw) {
        auto byteen = device_->mem_req_byteen;
        auto data = VDataCast<uint8_t*, MEM_BLOCK_SIZE>::get(device_->mem_req_data);
        
        // 2. 如果地址落在IO_COUT_ADDR范围内，处理器将数据写入print_bufs_中对应core的stringstream对象，并在遇到换行符时将缓冲区内容打印到控制台。
        if (byte_addr >= uint64_t(IO_COUT_ADDR)
         && byte_addr < (uint64_t(IO_COUT_ADDR) + IO_COUT_SIZE)) {
          // process console output
          for (int i = 0; i < IO_COUT_SIZE; i++) {
            if ((byteen >> i) & 0x1) {
              auto& ss_buf = print_bufs_[i];
              char c = data[i];
              ss_buf << c;
              if (c == '\n') {
                std::cout << std::dec << "#" << i << ": " << ss_buf.str() << std::flush;
                ss_buf.str("");
              }
            }
          }
        } else {
          // process writes
          /*
          printf("%0ld: [sim] MEM Wr Req: tag=0x%0lx, addr=0x%0lx, byteen=0x", timestamp, device_->mem_req_tag, byte_addr);
          for (int i = (MEM_BLOCK_SIZE/4)-1; i >= 0; --i) {
            printf("%x", (int)((byteen >> (4 * i)) & 0xf));
          }
          printf(", data=0x");
          for (int i = MEM_BLOCK_SIZE-1; i >= 0; --i) {
            printf("%d=%02x,", i, data[i]);
          }
          printf("\n");
          */
          for (int i = 0; i < MEM_BLOCK_SIZE; i++) {
            if ((byteen >> i) & 0x1) {
              (*ram_)[byte_addr + i] = data[i];
            }
          }
          // 写操作也生成一个请求对象，便于模拟DRAM延迟
          auto mem_req = new mem_req_t();
          mem_req->tag   = device_->mem_req_tag;
          mem_req->addr  = byte_addr;
          mem_req->write = true;
          mem_req->ready = true;  // 写请求不需要等待RAM读数据，所以ready直接设置为true

          // send dram request   
          dram_queue_.push(mem_req);  
        }
      } else {
        // process reads
        auto mem_req = new mem_req_t();
        mem_req->tag   = device_->mem_req_tag;
        mem_req->addr  = byte_addr;
        mem_req->write = false;
        mem_req->ready = false;   // 读请求需要等待RAM读数据回来，所以ready初始设置为false。
        ram_->read(mem_req->block.data(), byte_addr, MEM_BLOCK_SIZE);  // 仿真器中C++RAM是马上就把数据读出来了，但在真实的DRAM中是有延迟的，由dram模拟器完成延迟的模拟，mem_req->ready信号标志这一过程。
        pending_mem_reqs_.emplace_back(mem_req);  // 待处理列表

        //printf("%0ld: [sim] MEM Rd Req: addr=0x%0lx, tag=0x%0lx\n", timestamp, byte_addr, device_->mem_req_tag);

        // send dram request
        dram_queue_.push(mem_req);
      }
    }

    device_->mem_req_ready = running_;    // 标志信号，执行run()函数后，才可以开始接受内存请求。
  }

#endif

  void dcr_bus_reset() {
    device_->dcr_wr_valid = 0;
  }

  void dcr_bus_eval(bool clk) {
    if (!clk) {
      return;
    }  
    if (device_->dcr_wr_valid) {
      device_->dcr_wr_valid = 0;
    }
  }

  void wait(uint32_t cycles) {
    for (int i = 0; i < cycles; ++i) {
      this->tick();
    }
  }

private:

  typedef struct {
    Device* device;
    std::array<uint8_t, MEM_BLOCK_SIZE> block;
    uint64_t addr;  // 内存地址，单位是字节
    uint64_t tag;   // 请求标签，标注的是请求！不是cache中的那个tag。
    bool write;     
    bool ready;     // 标志位，用于dram延迟模拟，表示请求是否已经准备好（对于读请求来说，ready表示数据已经从RAM读出来了；对于写请求来说，ready可以直接设置为true，因为不需要等待RAM读数据）
  } mem_req_t;      // 访存数据包
  
  // 打印缓冲区，哈希表，key为每个core的id，value为用于存储该core的输出内容。
  // 待处理的内存请求列表。     读事务在这里排队，等DRAM延迟模拟完成后，再从这里取出准备好的请求，发送读响应。
  // DRAM请求队列，存储待发送到DRAM模拟器的内存请求。 读写事务都要进行DRAM延迟模拟。
  std::unordered_map<int, std::stringstream> print_bufs_;  
  std::list<mem_req_t*> pending_mem_reqs_;
  std::queue<mem_req_t*> dram_queue_;

  DramSim dram_sim_; // DRAM模拟器实例，只管延迟，不管数据。

  Device* device_;   // RTL实例

#ifdef VCD_OUTPUT
  VerilatedVcdC *tfp_;  
#endif

  RAM* ram_;         // 实际的数据仓库，只管数据，不管延迟。

  // 五个状态标志信号，实际可看作FSM，控制内存请求和响应的处理流程。
  // mem_bus 只需要rd这一组
  // axi_bus 需要rd和wr两组
  bool mem_rd_rsp_active_;
  bool mem_rd_rsp_ready_;

  bool mem_wr_rsp_active_;
  bool mem_wr_rsp_ready_;

  bool running_;
};

///////////////////////////////////////////////////////////////////////////////
Processor::Processor()
  : impl_(new Impl())   
{}

Processor::~Processor() {
  delete impl_;   
}
// 将attach_ram、run和dcr_write函数的调用转发给Impl实例的相应函数
void Processor::attach_ram(RAM* mem) {
  impl_->attach_ram(mem);
}

void Processor::run() {
  impl_->run();
}

void Processor::dcr_write(uint32_t addr, uint32_t value) {
  return impl_->dcr_write(addr, value);
}