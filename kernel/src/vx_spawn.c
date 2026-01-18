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

#include <vx_spawn.h>
#include <vx_intrinsics.h>
#include <vx_print.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

__thread dim3_t blockIdx;
__thread dim3_t threadIdx;
dim3_t gridDim;
dim3_t blockDim;

__thread uint32_t __local_group_id;
uint32_t __warps_per_group;

/*
  两个核心结构体，用于在主线程（Master Warp）和子线程（Slave Warps）之间传递参数。

  A. wspawn_groups_args_t (用于 Group 调度)
    当 block_dim > 1 时（即有线程组协作需求），使用这个结构体。
    成员解释：
      callback: 要执行的内核函数指针。
      arg:           传递给内核函数的参数指针。
      group_offset:    当前 Core 负责的第一个 Group 的全局索引偏移。
      warp_batches:    每个 Warp 需要执行多少批次的 Group。
      remaining_warps: 额外需要处理的 Warps 数量（用于处理不能整除的情况）。
      warps_per_group: 每个 Group 需要多少个 Warp。
      groups_per_core: 每个 Core 同时处理多少个 Group。
      remaining_mask: 用于最后一个 Warp 的线程掩码（如果 Group Size 不是 Warp Size 的整数倍）。
  B. wspawn_threads_args_t (用于 Task 调度)
    当 block_dim = 1 时（即每个任务独立），使用这个结构体。
    成员解释：
      callback: 要执行的内核函数指针。
      arg:           传递给内核函数的参数指针。
      all_tasks_offset: 当前 Core 负责的第一个任务的全局索引偏移。
      remain_tasks_offset: 当前 Core 负责的剩余任务的起始索引偏移（用于处理不能整除的情况）。
      warp_batches:    每个 Warp 需要执行多少批次的任务。
      remaining_warps: 额外需要处理的 Warps 数量（用于处理不能整除的情况）。  
*/
typedef struct {
	vx_kernel_func_cb callback;  // 用户要执行的 Kernel 函数指针
	const void* arg;             // 传给 Kernel 函数的参数指针
	uint32_t group_offset;       // 当前 Core 负责的起始 Group ID。          （group对应block概念，一个core可能分配了哪几个group）
	uint32_t warp_batches;       // warp需要激活执行几轮？                   （core硬件warp并行能力有限，而需要执行的warp硬件资源，所以需要分批执行多轮）
	uint32_t remaining_warps;    // 非整除情况0，最后一轮的warp数量。          （非整除情况的处理）
  uint32_t warps_per_group;    // 一个 Group 需要多少个硬件 Warp 来承载？   （group对应block，包含n个thread；硬件上warp可能支持m个thread执行，所以n/m个warp）
  uint32_t groups_per_core;    //  Core硬件支持同时能跑多少个 Group？       （core硬件warp数量/每个group需要的warp数量）
  uint32_t remaining_mask;     // 非整除情况1，最后一个 Warp 的有效线程掩码。（n/m的余数）
} wspawn_groups_args_t;

typedef struct {
	vx_kernel_func_cb callback;   // 要执行的内核函数指针。 
	const void* arg;              // 传递给内核函数的参数指针。
	uint32_t all_tasks_offset;    // 当前 Core 负责的第一个任务的全局索引偏移。
  uint32_t remain_tasks_offset; // 当前 Core 负责的剩余任务的起始索引偏移（用于处理不能整除的情况）。
	uint32_t warp_batches;        // warp需要激活执行几轮？
	uint32_t remaining_warps;     // 非整除情况0，最后一轮的warp数量。  
} wspawn_threads_args_t;

static void __attribute__ ((noinline)) process_threads() {
  // 1、从 MSCRATCH 读取调度参数
  wspawn_threads_args_t* targs = (wspawn_threads_args_t*)csr_read(VX_CSR_MSCRATCH);
  
  // 2、获取硬件线程信息
  uint32_t threads_per_warp = vx_num_threads();
  uint32_t warp_id = vx_warp_id();
  uint32_t thread_id = vx_thread_id();

  // 3、计算当前warp需要处理的任务范围
      // 3.1 这个warp硬件要执行的第一个warp软件ID是多少？ 
  uint32_t start_warp = (warp_id * targs->warp_batches) + MIN(warp_id, targs->remaining_warps);
      // 3.2 当前这个warp硬件，需要执行几轮？ 
  uint32_t iterations = targs->warp_batches + (warp_id < targs->remaining_warps);
  
  // 4、计算当前线程需要处理的任务ID范围
  uint32_t start_task_id = targs->all_tasks_offset + (start_warp * threads_per_warp) + thread_id;
  uint32_t end_task_id = start_task_id + iterations * threads_per_warp;

  __local_group_id = 0;
  threadIdx.x = 0;
  threadIdx.y = 0;
  threadIdx.z = 0;

  vx_kernel_func_cb callback = targs->callback;
  const void* arg = targs->arg;
  // 注意步长
  for (uint32_t task_id = start_task_id; task_id < end_task_id; task_id += threads_per_warp) {
    blockIdx.x = task_id % gridDim.x;
    blockIdx.y = (task_id / gridDim.x) % gridDim.y;
    blockIdx.z = task_id / (gridDim.x * gridDim.y);

    // 执行用户代码
    callback((void*)arg);
  }
}

static void __attribute__ ((noinline)) process_remaining_threads() {
  wspawn_threads_args_t* targs = (wspawn_threads_args_t*)csr_read(VX_CSR_MSCRATCH);

  uint32_t thread_id = vx_thread_id();
  uint32_t task_id = targs->remain_tasks_offset + thread_id;

  (targs->callback)((void*)targs->arg);
}

static void __attribute__ ((noinline)) process_threads_stub() {
  // activate all threads
  vx_tmc(-1);

  // process all tasks
  process_threads();

  // disable warp
  vx_tmc_zero();
}

// 涉及group到warp的调度
static void __attribute__ ((noinline)) process_thread_groups() {
  // 1、从 MSCRATCH 读取调度参数
  wspawn_groups_args_t* targs = (wspawn_groups_args_t*)csr_read(VX_CSR_MSCRATCH);
  // 2、获取硬件线程信息
  uint32_t threads_per_warp = vx_num_threads();
  uint32_t warp_id = vx_warp_id();
  uint32_t thread_id = vx_thread_id();
  // 3、group映射参数： 一个group需要多少warp来承载？ 每个core硬件支持并行跑多少group？
  uint32_t warps_per_group = targs->warps_per_group;
  uint32_t groups_per_core = targs->groups_per_core;
  // 4、计算当前warp的角色： 
      // 4.1 这个warp硬件需要执行几轮group？
  uint32_t iterations = targs->warp_batches + (warp_id < targs->remaining_warps);
      // 4.2 当前warp对应core硬件上这一轮group的第几个？
  uint32_t local_group_id = warp_id / warps_per_group;
      // 4.3 当前warp在所属group内是第几个warp？
  uint32_t group_warp_id = warp_id - local_group_id * warps_per_group;
      // 4.4 当前线程对应group内的第几个线程？  = (我是第几个 Warp * 每个 Warp 多少线程) + 我的线程 ID
  uint32_t local_task_id = group_warp_id * threads_per_warp + thread_id;

  // 5、计算当前线程需要处理的group ID范围
  uint32_t start_group = targs->group_offset + local_group_id;
  uint32_t end_group = start_group + iterations * groups_per_core;

  __local_group_id = local_group_id;

  threadIdx.x = local_task_id % blockDim.x;
  threadIdx.y = (local_task_id / blockDim.x) % blockDim.y;
  threadIdx.z = local_task_id / (blockDim.x * blockDim.y);

  vx_kernel_func_cb callback = targs->callback;
  const void* arg = targs->arg;

  // 注意步长
  for (uint32_t group_id = start_group; group_id < end_group; group_id += groups_per_core) {
    blockIdx.x = group_id % gridDim.x;
    blockIdx.y = (group_id / gridDim.x) % gridDim.y;
    blockIdx.z = group_id / (gridDim.x * gridDim.y);
    callback((void*)arg);
  }
}

static void __attribute__ ((noinline)) process_thread_groups_stub() {
  wspawn_groups_args_t* targs = (wspawn_groups_args_t*)csr_read(VX_CSR_MSCRATCH);

  uint32_t warps_per_group = targs->warps_per_group;
  uint32_t remaining_mask = targs->remaining_mask;        // 非整除情况1，最后一个 Warp 的有效线程掩码。
  uint32_t warp_id = vx_warp_id();                        // 当前硬件warp id        
  uint32_t group_warp_id = warp_id % warps_per_group;     // 当前warp在所属group内是第几个warp？
  uint32_t threads_mask = (group_warp_id == warps_per_group-1) ? remaining_mask : -1;   // group中的最后一个warp使用特殊掩码，其他warp全激活。

  // activate threads
  vx_tmc(threads_mask);

  // process thread groups
  process_thread_groups();

  // disable all warps except warp0
  // 这里这么写是因为 warp0 和 other warp 都是执行这个_stub 函数的；所以需要兼容。
  // 对比task调度的，就不需要这么写了。
  vx_tmc(0 == vx_warp_id());
}

int vx_spawn_threads(uint32_t dimension,             // grid 维度
                     const uint32_t* grid_dim,      // grid 大小
                     const uint32_t * block_dim,    // block 大小
                     vx_kernel_func_cb kernel_func, // kernel 函数指针；这是最后要执行的用户函数。
                     const void* arg) {             // 传递给 kernel 的参数
  // calculate number of groups and group size
  // ... 计算 num_groups (总 Block 数) 和 group_size (每个 Block 的线程数) ...
  // gridDim 和 blockDim 是全局变量，这里初始化它们供后续 Kernel 使用
  uint32_t num_groups = 1;
  uint32_t group_size = 1;
  for (uint32_t i = 0; i < 3; ++i) {
    uint32_t gd = (grid_dim && (i < dimension)) ? grid_dim[i] : 1;
    uint32_t bd = (block_dim && (i < dimension)) ? block_dim[i] : 1;
    num_groups *= gd;
    group_size *= bd;
    gridDim.m[i] = gd;
    blockDim.m[i] = bd;
  }

  // device specifications  
  // 获取硬件规格，见 kernel/include/vx_intrinsics.h，实际是读 CSR 寄存器
  uint32_t num_cores = vx_num_cores();
  uint32_t warps_per_core = vx_num_warps();
  uint32_t threads_per_warp = vx_num_threads();
  uint32_t core_id = vx_core_id();                        
/*
  check group size
  检查 group_size 是否超过每个核心的线程数。 
  约束： 在 SIMT 编程模型（如 CUDA/OpenCL）中，同一个 Block (Group) 内的所有线程必须能够在一个 Core 上同时“驻留” (Resident)。
       这样才能保证它们可以通过共享内存通信和同步 (__syncthreads)。
  1. 共享内存 (Shared Memory)：它们需要访问同一块高速缓存（L1 Cache / Shared Memory）。
      如果线程分散在不同的 Core 上，跨 Core 访问 L1 Cache 极其缓慢甚至不可能。
  2. 同步屏障 (__syncthreads)：当代码执行到 __syncthreads() 时，Block 内的所有线程都必须到达这个点才能继续。
      如果 Block 大于 Core 的容量，意味着有些线程根本没机会被调度上硬件（因为硬件槽位满了），那么已经在硬件上的线程就会永远等待那些还没上场的线程，导致死锁 (Deadlock)。
  
  因此，软件编程时：  Group Size (Block Size) 受限于 单个 Core 的硬件容量。
                    Grid Size (Total Blocks) 则几乎 无限，受限于显存大小和时间。
*/
  uint32_t threads_per_core = warps_per_core * threads_per_warp;
  if (threads_per_core < group_size) {
    vx_printf("error: group_size > threads_per_core (%d,%d)\n", group_size, threads_per_core);
    return -1;
  }

  /*
    2. 调度路径选择
      根据 group_size 决定走哪条调度路径。
      - 如果 group_size > 1，说明有线程组协作需求，走 Group 调度路径。
      - 如果 group_size = 1，说明每个任务独立，走 Task 调度路径。

    if (group_size > 1) {
        // 走 Group 调度路径 (类似 CUDA Block)
        // 必须保证同一个 Group 的线程在同一个 Core 上，以便共享内存和同步
    } else {
        // 走 Task 调度路径 (OpenCL Task / 独立线程)
        // 线程之间无关联，可以随意打散到任意 Core 的任意 Warp
    }
  */
  if (group_size > 1) {
    // calculate number of warps per group
    // group_size对应一个block中有多少thread，计算每个group需要多少warps来承载；
    // 在不可整除情况下，最后一个warp只用部分线程，需要计算mask。
    uint32_t warps_per_group = group_size / threads_per_warp;
    uint32_t remaining_threads = group_size - warps_per_group * threads_per_warp;
    uint32_t remaining_mask = -1;
    if (remaining_threads != 0) {
      remaining_mask = (1 << remaining_threads) - 1;
      ++warps_per_group;
    }

    // calculate necessary active cores
    // num_groups 是总 block 数，warps_per_group 是每个 block 需要多少 warp； 这里计算出总warp数；
    // needed_cores 是理想情况下需要多少 core 来跑完这些 warp；“+ warps_per_core-1” 是实现向上取整；
    // 理想值 和 硬件实际资源 取最小值，避免超额分配。
    uint32_t needed_warps = num_groups * warps_per_group;
    uint32_t needed_cores = (needed_warps + warps_per_core-1) / warps_per_core;
    uint32_t active_cores = MIN(needed_cores, num_cores);

    // only active cores participate。  
    // 如果当前core_id 超过了 active_cores 数量，说明这个 core 不需要参与计算，直接返回。
    if (core_id >= active_cores)
      return 0;

    // total number of groups per core
    // 平均每个core负责多少 group；非整除时，前 remaining_groups_per_core 个 core 多分配一个 group。
    uint32_t total_groups_per_core = num_groups / active_cores;
    uint32_t remaining_groups_per_core = num_groups - active_cores * total_groups_per_core;
    if (core_id < remaining_groups_per_core)
      ++total_groups_per_core;

    // calculate number of warps to activate
    uint32_t groups_per_core = warps_per_core / warps_per_group;             // 1.core硬件能同时跑几个group
    uint32_t total_warps_per_core = total_groups_per_core * warps_per_group; // 2.当前core一共需要跑多少warp
    // 计算core怎么激活warp，需要激活几次，非整除情况的处理。
    uint32_t active_warps = total_warps_per_core;                            
    uint32_t warp_batches = 1, remaining_warps = 0;
    if (active_warps > warps_per_core) {                        
      active_warps = groups_per_core * warps_per_group;
      warp_batches = total_warps_per_core / active_warps;
      remaining_warps = total_warps_per_core - warp_batches * active_warps;
    }

    // calculate offsets for group distribution 
    // 下式计算当前 core 负责的第一个 group 的全局索引偏移。  （理清楚每个group的分配方式）
    uint32_t group_offset = core_id * total_groups_per_core + MIN(core_id, remaining_groups_per_core);

    // set scheduler arguments
    wspawn_groups_args_t wspawn_args = {
      kernel_func,
      arg,
      group_offset,    
      warp_batches,
      remaining_warps,
      warps_per_group,
      groups_per_core,
      remaining_mask
    };
    // 这里把参数写进了 MSCRATCH 寄存器，子线程可以读出来。
    csr_write(VX_CSR_MSCRATCH, &wspawn_args);

    // set global variables          这种全局变量为什么需要设置？ 
    __warps_per_group = warps_per_group;

    // execute callback on other warps        这里和start.s中一样，warp0唤醒其他warp跳转到指定函数地址执行。warp0继续往下走，自己也执行这个函数。
    vx_wspawn(active_warps, process_thread_groups_stub);

    // execute callback on warp0
    process_thread_groups_stub();
  } else {
    uint32_t num_tasks = num_groups;     // group_size = 1; 这里的task、group粒度相当于thread粒度；
    __warps_per_group = 0;

    // calculate necessary active cores
    uint32_t needed_cores = (num_tasks + threads_per_core - 1) / threads_per_core;
    uint32_t active_cores = MIN(needed_cores, num_cores);

    // only active cores participate
    if (core_id >= active_cores)
      return 0;

    // number of tasks per core    
    // 计算每个core负责多少task; 粒度等效于要执行多少thread； 这里有非整除情况1，remaining_tasks_per_core。
    uint32_t tasks_per_core = num_tasks / active_cores;
    uint32_t remaining_tasks_per_core = num_tasks - tasks_per_core * active_cores;
    if (core_id < remaining_tasks_per_core)
      ++tasks_per_core;

    // calculate number of warps to activate     
    // task粒度还是要转换为warp粒度来执行；   这里会有非整除情况2，最后一个warp对应remaining_tasks。
    // warp粒度下，core硬件warp数限制； 这里会有非整除情况3，warp_batches和remaining_warps。
    uint32_t total_warps_per_core = tasks_per_core / threads_per_warp;
    uint32_t remaining_tasks = tasks_per_core - total_warps_per_core * threads_per_warp;  
    uint32_t active_warps = total_warps_per_core;
    uint32_t warp_batches = 1, remaining_warps = 0;
    if (active_warps > warps_per_core) {
      active_warps = warps_per_core;
      warp_batches = total_warps_per_core / active_warps;
      remaining_warps = total_warps_per_core - warp_batches * active_warps;
    }

    // calculate offsets for task distribution
    // 下式计算当前 core 负责的第一个 task 的全局索引偏移。  （理清楚每个task的分配方式）
    // 对应非整除情况2，计算当前core剩余task的起始偏移remain_tasks_offset。
    uint32_t all_tasks_offset = core_id * tasks_per_core + MIN(core_id, remaining_tasks_per_core);
    uint32_t remain_tasks_offset = all_tasks_offset + (tasks_per_core - remaining_tasks);

    // prepare scheduler arguments
    wspawn_threads_args_t wspawn_args = {
      kernel_func,
      arg,
      all_tasks_offset,
      remain_tasks_offset,
      warp_batches,
      remaining_warps
    };
    csr_write(VX_CSR_MSCRATCH, &wspawn_args);

    if (active_warps >= 1) {
      // execute callback on other warps  
      vx_wspawn(active_warps, process_threads_stub);

      // activate all threads
      vx_tmc(-1);

      // process threads
      process_threads();

      // back to single-threaded
      vx_tmc_one();
    }
    // 主warp处理剩余task（非整除情况2）
    if (remaining_tasks != 0) {
      // activate remaining threads
      uint32_t tmask = (1 << remaining_tasks) - 1;
      vx_tmc(tmask);

      // process remaining threads
      process_remaining_threads();

      // back to single-threaded
      vx_tmc_one();
    }
  }

  // wait for spawned warps to complete
  vx_wspawn(1, 0);

  return 0;
}

#ifdef __cplusplus
}
#endif

/*
3. 路径一：Group 调度 (process_thread_groups)
  当 block_dim > 1 时（例如 CUDA 中的 blockDim.x = 32），这些线程必须被调度到同一个 Core 上，以便它们可以通过 Shared Memory 通信和同步 (__syncthreads)。

  调度逻辑：
    计算 Warps per Group：一个软件 Group 需要多少个硬件 Warp？
        例如：Group Size = 64，硬件 Warp Size = 32 -> 需要 2 个 Warp。
    计算 Groups per Core：一个 Core 能同时跑多少个 Group？
    Warp 映射：
        local_group_id = warp_id / warps_per_group
        这意味着相邻的几个 Warp 会被绑定到同一个 Group ID 上。
    循环执行：如果任务太多，硬件 Warp 不够用，就采用 Warp Batches（分批次）的方式。跑完一批，再跑下一批。

4. 路径二：Task 调度 (process_threads)
  当 block_dim = 1 时（每个任务都是独立的），调度更灵活。

  调度逻辑：
      扁平化：把所有任务看作一个巨大的线性数组。
      均匀切分：把这个数组切成 N 份（N = Active Cores），每个 Core 领一份。
      Warp 切分：在 Core 内部，再把任务切给每个 Warp。
      Thread 切分：在 Warp 内部，每个 Thread 领一个任务。

*/

/*
3. 涉及的 C 语言语法点
__attribute__ ((noinline))：

  含义：告诉编译器“千万不要把这个函数内联（Inline）展开”。
  作用：在这里非常重要。因为 vx_wspawn 接受的是函数指针，如果编译器把函数内联优化掉了，就没有函数地址可以传给硬件了。

__thread：

  含义：线程局部存储（TLS）修饰符。
  作用：__thread dim3_t blockIdx; 意味着每个硬件线程都有一份独立的 blockIdx 变量，互不干扰。
  
csr_read(VX_CSR_MSCRATCH) 与 指针强转：

  wspawn_groups_args_t* targs = (wspawn_groups_args_t*)csr_read(VX_CSR_MSCRATCH);
  含义：csr_read 返回的是一个整数（寄存器里的值）。我们把它强制转换成结构体指针。
  背景：主线程把结构体在栈上的地址写进了 MSCRATCH 寄存器，子线程读出来，就能访问主线程栈上的数据了。这是共享内存架构下的参数传递黑科技。

*/