#include "tests.h"
#include <stdio.h>
#include <algorithm>
// 配置vortex硬件参数后，build生成的与硬件强相关的头文件
#include <VX_config.h>
#include <vx_intrinsics.h>
#include <vx_print.h>
#include <vx_spawn.h>

///////////////////////////////////////////////////////////////////////////////
// 三个 Helper Functions：
// 1. check_error: 检查 buffer 中的数据是否正确。
// 2. make_select_tmask: 根据线程ID生成仅该线程激活的线程掩码。
// 3. make_full_tmask: 根据线程数生成全部线程激活的线程掩码。
int __attribute__((noinline)) check_error(const int* buffer, int offset, int size) {
	int errors = 0;
	for (int i = offset; i < size; i++)	{
		int value = buffer[i];
		int ref_value = 65 + i;
		if (value == ref_value)	{
			//PRINTF("[%d] %c\n", i, value);
		} else {
			PRINTF("*** error: [%d] 0x%x, expected 0x%x\n", i, value, ref_value);
			++errors;
		}
	}
	return errors;
}

int __attribute__((noinline)) make_select_tmask(int tid) {
	return (1 << tid);
}

int __attribute__((noinline)) make_full_tmask(int num_threads) {
	return (1 << num_threads) - 1;
}

///////////////////////////////////////////////////////////////////////////////
// test 0: Global Memory 测试：所有线程写入自己的线程ID加上65到global_buffer中。
#define GLOBAL_MEM_SZ 8
int global_buffer[GLOBAL_MEM_SZ];

int test_global_memory() {
	PRINTF("Global Memory Test\n");

	for (int i = 0; i < GLOBAL_MEM_SZ; i++) {
		global_buffer[i] = 65 + i;
	}

	return check_error(global_buffer, 0, GLOBAL_MEM_SZ);
}

///////////////////////////////////////////////////////////////////////////////
// test 1 :Local Memory 测试：激活8个线程，每个线程写入自己的线程ID加上65到lmem_addr中，然后读回到lmem_buffer中。
// 这里volatile很重要，下面wr测试的时候，如果没有volatile，编译器会把对lmem_addr的写操作优化掉。
volatile int* lmem_addr = (int*)LMEM_BASE_ADDR;

int lmem_buffer[8];

void __attribute__((noinline)) do_lmem_wr() {
	unsigned tid = vx_thread_id();
	lmem_addr[tid] = 65 + tid;  //store
	int x = lmem_addr[tid];		//load   这里是一个RAW hazard测试
	lmem_addr[tid] = x;			//store
}

void __attribute__((noinline)) do_lmem_rd() {
	unsigned tid = vx_thread_id();
	lmem_buffer[tid] = lmem_addr[tid];
}

int test_local_memory() {
	PRINTF("Local Memory Test\n");

	int num_threads = std::min(vx_num_threads(), 8);
	int tmask = make_full_tmask(num_threads);
	vx_tmc(tmask);
	do_lmem_wr();
	do_lmem_rd();  
	vx_tmc_one();

	return check_error(lmem_buffer, 0, num_threads);
}

///////////////////////////////////////////////////////////////////////////////
// test 2 : TMC 测试：激活8个线程，每个线程写入自己的线程ID加上65到buffer中。
int tmc_buffer[8];

void __attribute__((noinline)) do_tmc() {
	unsigned tid = vx_thread_id();
	tmc_buffer[tid] = 65 + tid;
}

int test_tmc() {
	PRINTF("TMC Test\n");

	int num_threads = std::min(vx_num_threads(), 8);
	int tmask = make_full_tmask(num_threads);
	vx_tmc(tmask);  
	do_tmc();		
	vx_tmc_one();	

	return check_error(tmc_buffer, 0, num_threads);
}

///////////////////////////////////////////////////////////////////////////////
// test 3 : PRED 测试：激活8个线程，只有线程0会写入65到buffer中，其他线程不会写入任何东西。
// 简单条件执行场景，不需要分支发散
int pred_buffer[8];

void __attribute__((noinline)) do_pred() {
	unsigned tid = vx_thread_id();
	vx_pred((tid == 0), 1);
	pred_buffer[tid] = 65;
}

int test_pred() {
	PRINTF("PRED Test\n");
	int num_threads = std::min(vx_num_threads(), 8);
	int tmask = make_full_tmask(num_threads);
	// 这一段是为了跟通用的check_error逻辑匹配。
	for (int i = 1; i < num_threads; i++) {
		pred_buffer[i] = 65 + i;
	}

	vx_tmc(tmask);
	do_pred();
	vx_tmc_one();

	return check_error(pred_buffer, 0, num_threads);
}

///////////////////////////////////////////////////////////////////////////////
// test 4 : WSPAWN 测试：激活8个warp，每个warp写入自己的warpID加上65到buffer中。
int wspawn_buffer[8];

void wspawn_kernel() {
	unsigned wid = vx_warp_id();
	wspawn_buffer[wid] = 65 + wid;
	vx_tmc(0 == wid);
}

int test_wsapwn() {
	PRINTF("Wspawn Test\n");
	int num_warps = std::min(vx_num_warps(), 8);
	vx_wspawn(num_warps, wspawn_kernel);
	wspawn_kernel();

	return check_error(wspawn_buffer, 0, num_warps);
}

///////////////////////////////////////////////////////////////////////////////
// test 5 : Control Divergence 测试：激活4个线程，线程0写入'A'，线程1写入'B'，线程2写入'C'，线程3写入'D'。
int dvg_buffer[4];

void __attribute__((noinline)) __attribute__((optimize("O1"))) do_divergence() {
	int tid = vx_thread_id();
	int cond1 = tid < 2;
	int sp1 = vx_split(cond1);
	if (cond1) {
		// 两个{}块，
		{
			int cond2 = tid < 1;
			int sp2 = vx_split(cond2);
			if (cond2) {
				dvg_buffer[tid] = 65; // A
			} else {
				dvg_buffer[tid] = 66; // B
			}
			vx_join(sp2);
		}
		// always false，边界case: 全假分支处理，硬件如何处理？
		{
			int cond3 = tid < 0;    
			int sp3 = vx_split(cond3);
			if (cond3) {
				dvg_buffer[tid] = 67; // C
			}
			vx_join(sp3);
		}
	} else {
		{
			int cond2 = tid < 3;
			int sp2 = vx_split(cond2);
			if (cond2) {
				dvg_buffer[tid] = 67; // C
			} else {
				dvg_buffer[tid] = 68; // D
			}
			vx_join(sp2);
		}
	}
	vx_join(sp1);
}

int test_divergence() {
	PRINTF("Control Divergence Test\n");

	int num_threads = std::min(vx_num_threads(), 4);
	int tmask = make_full_tmask(num_threads);
	vx_tmc(tmask);
	do_divergence();
	vx_tmc_one();

	return check_error(dvg_buffer, 0, num_threads);
}

///////////////////////////////////////////////////////////////////////////////
// test 6 : Spawn Tasks 测试：生成8个任务，每个任务将arg.src中的对应元素复制到arg.dst中。
// 查阅vx_spawn.c 中vx_spawn_threads()函数原型。
// 软件层的grid、block、task 映射到 硬件层的 core、warp、thread
// 这个测试就是task粒度调度，不需要分block调度。   
#define ST_BUF_SZ 8
typedef struct {
	int * src;
	int * dst;
} st_args_t;

int st_buffer_src[ST_BUF_SZ];
int st_buffer_dst[ST_BUF_SZ];

void st_kernel(const st_args_t * __UNIFORM__ arg) {
  arg->dst[blockIdx.x] = arg->src[blockIdx.x];
}

int test_spawn_tasks() {
	PRINTF("SpawnTasks Test\n");

	st_args_t arg;
	arg.src = st_buffer_src;
	arg.dst = st_buffer_dst;

	for (int i = 0; i < ST_BUF_SZ; i++) {
		st_buffer_src[i] = 65 + i;
	}

	uint32_t num_tasks(ST_BUF_SZ);
	vx_spawn_threads(1, &num_tasks, nullptr, (vx_kernel_func_cb)st_kernel, &arg);

	return check_error(st_buffer_dst, 0, ST_BUF_SZ);
}

///////////////////////////////////////////////////////////////////////////////
// test 7 : Serial Function Call 测试：激活8个线程，所有线程串行执行sr_kernel函数，函数中每个线程写入自己的线程ID加上65到buffer中。
// 看 vx_serial.s 中 vx_serial() 函数原型。
typedef struct {
	int * buf;
} sr_args_t;

int sr_buffer[8];

void sr_kernel(const sr_args_t * arg) {
	int tid = vx_thread_id();
  	arg->buf[tid] = 65 + tid;
}

void __attribute__((noinline)) do_serial() {
	sr_args_t arg;
	arg.buf = sr_buffer;
	vx_serial((vx_serial_cb)sr_kernel, &arg);
}

int test_serial() {
	PRINTF("Serial Test\n");
	int num_threads = std::min(vx_num_threads(), 8);
	int tmask = make_full_tmask(num_threads);
	vx_tmc(tmask);
	do_serial();
	vx_tmc_one();

	return check_error(sr_buffer, 0, num_threads);
}

///////////////////////////////////////////////////////////////////////////////
// test 8 : TMC Test 测试：8个线程依次执行do_tmask函数，函数中每个线程写入自己的线程掩码加上65到buffer中。
// 设计目的： 验证 线程掩码（Thread Mask）动态切换 和 程序计数器（PC）/ 寄存器状态 在频繁上下文切换中的正确性。
int tmask_buffer[8];

int __attribute__((noinline)) do_tmask() {
	int tid = vx_thread_id();
	int tmask = make_select_tmask(tid);
	int cur_tmask = vx_active_threads();
	tmask_buffer[tid] = (cur_tmask == tmask) ? (65 + tid) : 0;
	return tid + 1;
}

int test_tmask() {
	PRINTF("Thread Mask Test\n");

	// activate all thread
	vx_tmc(-1);

	int num_threads = std::min(vx_num_threads(), 8);
	int tid = 0;

l_start:
	int tmask = make_select_tmask(tid);
	vx_tmc(tmask);
	tid = do_tmask();
	if (tid < num_threads)
		goto l_start;
	vx_tmc_one();

	return check_error(tmask_buffer, 0, num_threads);
}

///////////////////////////////////////////////////////////////////////////////
// test 9 : Barrier Test 测试：激活8个warp，每个warp写入自己的warpID加上65到buffer中，然后在barrier处同步。
// 设计目的： 验证 barrier 指令在warp级别的同步正确性。
int barrier_buffer[8];
volatile int barrier_ctr;
volatile int barrier_stall;

void barrier_kernel() {
	unsigned wid = vx_warp_id();
	// for循环延时
	for (int i = 0; i <= (wid * 256); ++i) {
		++barrier_stall;
	}
	barrier_buffer[wid] = 65 + wid;
	vx_barrier(0, barrier_ctr);
	vx_tmc(0 == wid);  // warp0继续执行，其他warp结束
}

int test_barrier() {
	PRINTF("Barrier Test\n");
	int num_warps = std::min(vx_num_warps(), 8);
	barrier_ctr = num_warps;
	barrier_stall = 0;
	vx_wspawn(num_warps, barrier_kernel);
	barrier_kernel();
	return check_error(barrier_buffer, 0, num_warps);
}

///////////////////////////////////////////////////////////////////////////////
//	test 10 : TLS Test 测试：激活8个warp，每个warp写入自己的warpID加上65到tls_buffer中。
//	设计目的： 验证每个warp拥有独立的线程本地存储（Thread Local Storage, TLS）。
int tls_buffer[8];      // 普通的全局变量
__thread int tls_var;   // __thread前缀，线程本地存储变量

__attribute__((noinline)) void print_tls_var() {
	unsigned wid = vx_warp_id();
	tls_buffer[wid] = 65 + tls_var;
}

void tls_kernel() {
	unsigned wid = vx_warp_id();
	tls_var = wid;
	print_tls_var();
	vx_tmc(0 == wid);
}

int test_tls() {
	PRINTF("TLS Test\n");
	int num_warps = std::min(vx_num_warps(), 8);
	vx_wspawn(num_warps, tls_kernel);
	tls_kernel();
	return check_error(tls_buffer, 0, num_warps);
}