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

#include <common.h>

#include <mem.h>
#include <util.h>
#include <processor.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <iostream>
#include <future>
#include <list>
#include <chrono>

using namespace vortex;

/*
  初始化和析构：  初始化内存和处理器，确保异步任务完成。
  设备能力查询：  获取设备的各种能力信息。
  内存管理：      提供内存分配、保留、释放、访问和信息查询功能。
  程序上传和下载：    将程序上传到设备内存或从设备内存下载程序。
  仿真启动和等待：    启动仿真并等待其完成。
  设备控制寄存器读写：读写设备控制寄存器。
  MPM 查询：         查询 MPM 信息。
*/

class vx_device {
public:
  vx_device()
    : ram_(0, RAM_PAGE_SIZE)
    , global_mem_(ALLOC_BASE_ADDR,
                  GLOBAL_MEM_SIZE - ALLOC_BASE_ADDR,
                  RAM_PAGE_SIZE,
                  CACHE_BLOCK_SIZE)
  {
    processor_.attach_ram(&ram_);
  }

  ~vx_device() {
    if (future_.valid()) {
      future_.wait();
    }
  }

  int init() {
    return 0;
  }

  int get_caps(uint32_t caps_id, uint64_t *value) {
    uint64_t _value;
    switch (caps_id) {
    case VX_CAPS_VERSION:
      _value = IMPLEMENTATION_ID;
      break;
    case VX_CAPS_NUM_THREADS:
      _value = NUM_THREADS;
      break;
    case VX_CAPS_NUM_WARPS:
      _value = NUM_WARPS;
      break;
    case VX_CAPS_NUM_CORES:
      _value = NUM_CORES * NUM_CLUSTERS;
      break;
    case VX_CAPS_CACHE_LINE_SIZE:
      _value = CACHE_BLOCK_SIZE;
      break;
    case VX_CAPS_GLOBAL_MEM_SIZE:
      _value = GLOBAL_MEM_SIZE;
      break;
    case VX_CAPS_LOCAL_MEM_SIZE:
      _value = (1 << LMEM_LOG_SIZE);
      break;
    case VX_CAPS_ISA_FLAGS:
      _value = ((uint64_t(MISA_EXT))<<32) | ((log2floor(XLEN)-4) << 30) | MISA_STD;
      break;
    default:
      std::cout << "invalid caps id: " << caps_id << std::endl;
      std::abort();
      return -1;
    }
    *value = _value;
    return 0;
  }

  int mem_alloc(uint64_t size, int flags, uint64_t* dev_addr) {
    uint64_t addr;
    CHECK_ERR(global_mem_.allocate(size, &addr), {
      return err;
    });
    CHECK_ERR(this->mem_access(addr, size, flags), {
      global_mem_.release(addr);
      return err;
    });
    *dev_addr = addr;
    return 0;
  }

  int mem_reserve(uint64_t dev_addr, uint64_t size, int flags) {
    CHECK_ERR(global_mem_.reserve(dev_addr, size), {
      return err;
    });
    CHECK_ERR(this->mem_access(dev_addr, size, flags), {
      global_mem_.release(dev_addr);
      return err;
    });
    return 0;
  }

  int mem_free(uint64_t dev_addr) {
    return global_mem_.release(dev_addr);
  }

  int mem_access(uint64_t dev_addr, uint64_t size, int flags) {
    uint64_t asize = aligned_size(size, CACHE_BLOCK_SIZE);
    if (dev_addr + asize > GLOBAL_MEM_SIZE)
      return -1;

    if (flags | VX_MEM_WRITE) {
      flags |= VX_MEM_READ; // ensure caches can handle fill requests
    }

    ram_.set_acl(dev_addr, size, flags);

    return 0;
  }

  int mem_info(uint64_t* mem_free, uint64_t* mem_used) const {
    if (mem_free)
      *mem_free = global_mem_.free();
    if (mem_used)
      *mem_used = global_mem_.allocated();
    return 0;
  }

  int upload(uint64_t dest_addr, const void* src, uint64_t size) {
    uint64_t asize = aligned_size(size, CACHE_BLOCK_SIZE);
    if (dest_addr + asize > GLOBAL_MEM_SIZE)
      return -1;

    ram_.enable_acl(false);
    ram_.write((const uint8_t*)src, dest_addr, size);
    ram_.enable_acl(true);

    /*printf("VXDRV: upload %ld bytes from 0x%lx:", size, uintptr_t((uint8_t*)src));
    for (int i = 0;  i < (asize / CACHE_BLOCK_SIZE); ++i) {
      printf("\n0x%08lx=", dest_addr + i * CACHE_BLOCK_SIZE);
      for (int j = 0;  j < CACHE_BLOCK_SIZE; ++j) {
        printf("%02x", *((uint8_t*)src + i * CACHE_BLOCK_SIZE + CACHE_BLOCK_SIZE - 1 - j));
      }
    }
    printf("\n");*/

    return 0;
  }

  int download(void* dest, uint64_t src_addr, uint64_t size) {
    uint64_t asize = aligned_size(size, CACHE_BLOCK_SIZE);
    if (src_addr + asize > GLOBAL_MEM_SIZE)
      return -1;

    ram_.enable_acl(false);
    ram_.read((uint8_t*)dest, src_addr, size);
    ram_.enable_acl(true);

    /*printf("VXDRV: download %ld bytes to 0x%lx:", size, uintptr_t((uint8_t*)dest));
    for (int i = 0;  i < (asize / CACHE_BLOCK_SIZE); ++i) {
      printf("\n0x%08lx=", src_addr + i * CACHE_BLOCK_SIZE);
      for (int j = 0;  j < CACHE_BLOCK_SIZE; ++j) {
        printf("%02x", *((uint8_t*)dest + i * CACHE_BLOCK_SIZE + CACHE_BLOCK_SIZE - 1 - j));
      }
    }
    printf("\n");*/

    return 0;
  }

  int start(uint64_t krnl_addr, uint64_t args_addr) {
    // ensure prior run completed
    if (future_.valid()) {
      future_.wait();
    }

    // set kernel info
    this->dcr_write(VX_DCR_BASE_STARTUP_ADDR0, krnl_addr & 0xffffffff);
    this->dcr_write(VX_DCR_BASE_STARTUP_ADDR1, krnl_addr >> 32);
    this->dcr_write(VX_DCR_BASE_STARTUP_ARG0, args_addr & 0xffffffff);
    this->dcr_write(VX_DCR_BASE_STARTUP_ARG1, args_addr >> 32);

    // start new run
    future_ = std::async(std::launch::async, [&]{
      processor_.run();
    });

    // clear mpm cache
    mpm_cache_.clear();

    return 0;
  }

  int ready_wait(uint64_t timeout) {
    if (!future_.valid())
      return 0;
    uint64_t timeout_sec = timeout / 1000;
    std::chrono::seconds wait_time(1);
    for (;;) {
      // wait for 1 sec and check status
      auto status = future_.wait_for(wait_time);
      if (status == std::future_status::ready)
        break;
      if (0 == timeout_sec--)
        return -1;
    }
    return 0;
  }

  int dcr_write(uint32_t addr, uint32_t value) {
    if (future_.valid()) {
      future_.wait(); // ensure prior run completed
    }
    processor_.dcr_write(addr, value);
    dcrs_.write(addr, value);
    return 0;
  }

  int dcr_read(uint32_t addr, uint32_t* value) const {
    return dcrs_.read(addr, value);
  }

  int mpm_query(uint32_t addr, uint32_t core_id, uint64_t* value) {
    uint32_t offset = addr - VX_CSR_MPM_BASE;
    if (offset > 31)
      return -1;
    if (mpm_cache_.count(core_id) == 0) {
      uint64_t mpm_mem_addr = IO_MPM_ADDR + core_id * 32 * sizeof(uint64_t);
      CHECK_ERR(this->download(mpm_cache_[core_id].data(), mpm_mem_addr, 32 * sizeof(uint64_t)), {
        return err;
      });
    }
    *value = mpm_cache_.at(core_id).at(offset);
    return 0;
  }

/*
ram_：内存模块。
processor_：处理器对象。
global_mem_：全局内存分配器。
dcrs_：设备控制寄存器配置。
future_：异步任务的 std::future 对象。
mpm_cache_：MPM 缓存。
*/

private:

  RAM                 ram_;
  Processor           processor_;
  MemoryAllocator     global_mem_;
  DeviceConfig        dcrs_;
  std::future<void>   future_;
  std::unordered_map<uint32_t, std::array<uint64_t, 32>> mpm_cache_;
};

// .inc 文件通常是包含文件（include file），它们通常包含代码片段或宏定义，可以在多个源文件中重复使用。
// .inc 文件的内容通常通过预处理器指令 #include 包含到其他源文件中。
// 这个文件中包含了一些回调函数的定义，这些函数使用了 上面定义的 vx_device 类的成员函数。
/* 回调函数中包含的功能有：
设备管理：打开设备、关闭设备、获取设备能力。
内存管理：分配内存、保留内存、释放内存、访问内存、获取内存地址、获取内存信息。
数据传输：将数据从主机传输到设备、将数据从设备传输到主机。
仿真控制：启动仿真、等待仿真完成。
设备控制寄存器：读取和写入设备控制寄存器。
MPM 查询：查询 MPM 信息。
*/
#include <callbacks.inc>