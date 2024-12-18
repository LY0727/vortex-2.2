#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <CL/opencl.h>   // OpenCL headers
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <chrono>
#include <vector>
#include "common.h"   // user headers；Common definitions

#define KERNEL_NAME "sgemm"

#define FLOAT_ULP 6
/*************************************************************
 *                 OpenCL error checking
 * _err: OpenCL error code 
*************************************************************/
// OpenCL error checking  检查函数调用的返回值
#define CL_CHECK(_expr)                                                \
   do {                                                                \
     cl_int _err = _expr;                                              \
     if (_err == CL_SUCCESS)                                           \
       break;                                                          \
     printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err);   \
	  cleanup();			                                                     \
     exit(-1);                                                         \
   } while (0)

#define CL_CHECK2(_expr)                                               \
   ({                                                                  \
     cl_int _err = CL_INVALID_VALUE;                                   \
     decltype(_expr) _ret = _expr;                                     \
     if (_err != CL_SUCCESS) {                                         \
       printf("OpenCL Error: '%s' returned %d!\n", #_expr, (int)_err); \
	   cleanup();			                                                   \
       exit(-1);                                                       \
     }                                                                 \
     _ret;                                                             \
   })

//====================  test逻辑     ====================
//=======================================================
// 生成和比较不同类型的数据
template <typename Type>
class Comparator {};
// int
template <>
class Comparator<int> {
public:
  static const char* type_str() {
    return "integer";
  }
  static int generate() {
    return rand();
  }
  // errors: 应该判断是否大于吧
  static bool compare(int a, int b, int index, int errors) {
    if (a != b) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%d, actual=%d\n", index, a, b);
      }
      return false;
    }
    return true;
  }
};
// float
template <>
class Comparator<float> {
public:
  static const char* type_str() {
    return "float";
  }
  static int generate() {
    return static_cast<float>(rand()) / RAND_MAX;
  }
  static bool compare(float a, float b, int index, int errors) {
    union fi_t { float f; int32_t i; };
    fi_t fa, fb;
    fa.f = a;
    fb.f = b;
    auto d = std::abs(fa.i - fb.i);
    if (d > FLOAT_ULP) {
      if (errors < 100) {
        printf("*** error: [%d] expected=%f, actual=%f\n", index, a, b);
      }
      return false;
    }
    return true;
  }
};


// CPU implementation of sgemm   
// 矩阵数据的存储顺序是列优先；这里是 左列乘右行 得到C的第一行；我们一般写法是 左行*右列 得到C的第一行
static void sgemm_cpu(TYPE *C, const TYPE* A, const TYPE *B, int M, int N, int K) {
  for (int m = 0; m < M; ++m) {
    for (int n = 0; n < N; ++n) {
      TYPE acc = 0;
      for (int k = 0; k < K; ++k) {
          acc += A[k * M + m] * B[n * K + k];
      }
      C[n * M + m] = acc;
    }
  }
}

//====================  host逻辑     ====================
//=======================================================
// 读取内核文件，将文件内容读取到data指向的内存中
static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
  if (nullptr == filename || nullptr == data || 0 == size)
    return -1;

  FILE* fp = fopen(filename, "r");
  if (NULL == fp) {
    fprintf(stderr, "Failed to load kernel.");
    return -1;
  }
  // 将文件指针移动到文件末尾；获取文件大小；将文件指针移动到文件开头
  fseek(fp , 0 , SEEK_END);
  long fsize = ftell(fp);
  rewind(fp);
   // 为文件内容分配内存，并读取文件内容到data指向的内存中。
  *data = (uint8_t*)malloc(fsize);
  *size = fread(*data, 1, fsize, fp);

  fclose(fp);

  return 0;
}

//====================  命令行参数解析     ====================
//============================================================
uint32_t size = 32;
static void show_usage() {
  printf("Usage: [-n size] [-h: help]\n");
}

// parse_args 用于解析命令行参数，设置 size 的值，并进行参数验证。如果参数无效或用户请求帮助，程序会打印使用说明并退出。
// getopt 是一个用于解析命令行参数的函数; "n:h?" 是选项字符串，表示程序接受 -n 和 -h 选项，? 表示未知选项。
// getopt 会返回下一个选项字符，如果没有选项字符了，返回 -1。
// optarg 是 getopt 的全局变量，表示当前选项的参数。
// atoi 是将字符串转换为整数的函数。
static void parse_args(int argc, char **argv) {
  int c;
  while ((c = getopt(argc, argv, "n:h?")) != -1) {
    switch (c) {
    case 'n':
      size = atoi(optarg);
      break;
    case 'h':
    case '?': {
        show_usage();
        exit(0);
      } break;
    default:
      show_usage();
      exit(-1);
    }
  }

  if (size < 2) {
    printf("Error: invalid size!\n");
    exit(-1);
  }

  printf("Workload size=%d\n", size);
}

//====================  openCL object信息     ====================
//===============================================================
// OpenCL objects
cl_device_id     device_id    = NULL;
cl_context       context      = NULL;
cl_command_queue commandQueue = NULL;
cl_program       program      = NULL;
cl_kernel        kernel       = NULL;
cl_mem           a_memobj     = NULL;
cl_mem           b_memobj     = NULL;
cl_mem           c_memobj     = NULL;
uint8_t  *kernel_bin  = NULL;
//  Clean up OpenCL objects and release memory resources after the program has finished. 
static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (a_memobj) clReleaseMemObject(a_memobj);
  if (b_memobj) clReleaseMemObject(b_memobj);
  if (c_memobj) clReleaseMemObject(c_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);

  if (kernel_bin) free(kernel_bin);
}

//====================  命令行参数解析     ====================
//============================================================
int main (int argc, char **argv) {
    // parse command arguments
    // size 平方
  parse_args(argc, argv);
  uint32_t size_sq = size * size;
    // 平台ID   内核尺寸
  cl_platform_id platform_id;
  size_t kernel_size;
    // 随机数种子；使得每次运行程序时，生成的随机数序列相同；对于调式来说，结果具有可复现性。
  srand(50);

    // Getting platform and device information
  CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
  CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));

  printf("Create context\n");
  context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL,  &_err));

  // Allocate device buffers  计算所需内存大小，从上下文看，这里size_sq 是 size * size 的矩阵元素个数
  size_t nbytes = size_sq * sizeof(TYPE);
  a_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
  b_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, nbytes, NULL, &_err));
  c_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, nbytes, NULL, &_err));
  
  // 查看内核读取函数；kernel_bin 是一个指针，指向读取的kernel.bin文件的数据；kernel_size 是普通变量，内核文件的大小（字节数）
  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));

  // Build program
  CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));

  // Create kernel
  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  // Set kernel arguments
  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&a_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&b_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&c_memobj));
  CL_CHECK(clSetKernelArg(kernel, 3, sizeof(size), (void*)&size));

//===============  这里生成输入数据是test逻辑     ====================
  // Allocate memories for input arrays and output arrays.
  std::vector<TYPE> h_a(size_sq);
  std::vector<TYPE> h_b(size_sq);
  std::vector<TYPE> h_c(size_sq);

  // Generate input values
  for (uint32_t i = 0; i < size_sq; ++i) {
    h_a[i] = Comparator<TYPE>::generate();
    h_b[i] = Comparator<TYPE>::generate();
  }
//===============  host代码    ====================
  size_t global_offset[2] = {0, 0};
  size_t global_work_size[2] = {size, size};
  size_t local_work_size[2] = {1, 1};

  // Creating command queue
  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));
  // 上传输入数据到device
	printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, a_memobj, CL_TRUE, 0, nbytes, h_a.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, b_memobj, CL_TRUE, 0, nbytes, h_b.data(), 0, NULL, NULL));
  // 执行kernel，测量执行时间
  printf("Execute the kernel\n");
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 2, global_offset, global_work_size, local_work_size, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);
  // 下载结果数据到host
  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, c_memobj, CL_TRUE, 0, nbytes, h_c.data(), 0, NULL, NULL));
  // 验证结果
  printf("Verify result\n");
  std::vector<TYPE> h_ref(size_sq);
  sgemm_cpu(h_ref.data(), h_a.data(), h_b.data(), size, size, size);
  int errors = 0;
    // 这里erross是错误个数,有一个错误就failed; 前100个错误会打印出来。
  for (uint32_t i = 0; i < size_sq; ++i) {
    if (!Comparator<TYPE>::compare(h_c[i], h_ref[i], i, errors)) {
      ++errors;
    }
  }
  if (errors != 0) {
    printf("FAILED! - %d errors\n", errors);
  } else {
    printf("PASSED!\n");
  }
  // Clean up
  cleanup();

  return errors;
}
