#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <CL/opencl.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <chrono>
#include <vector>

#define FLOAT_ULP 6

#define KERNEL_NAME "conv3"

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

static int read_kernel_file(const char* filename, uint8_t** data, size_t* size) {
  if (nullptr == filename || nullptr == data || 0 == size)
    return -1;

  FILE* fp = fopen(filename, "r");
  if (NULL == fp) {
    fprintf(stderr, "Failed to load kernel.");
    return -1;
  }

  fseek(fp , 0 , SEEK_END);
  long fsize = ftell(fp);
  rewind(fp);

  *data = (uint8_t*)malloc(fsize);
  *size = fread(*data, 1, fsize, fp);

  fclose(fp);

  return 0;
}

static bool compare_equal(float a, float b) {
  union fi_t { float f; int32_t i; };
  fi_t fa, fb;
  fa.f = a;
  fb.f = b;
  auto d = std::abs(fa.i - fb.i);
  return d <= FLOAT_ULP;
}

static void convolution_cpu(float *O, float *I, float *W, int32_t width, int32_t height) {
  int paddedWidth = width + 2;
  for (int32_t y = 0; y < height; ++y) {
    for (int32_t x = 0; x < width; ++x) {
      int paddedY = y + 1;
      int paddedX = x + 1;
      float sum = 0.0f;
      for (int32_t ky = -1; ky <= 1; ++ky) {
        for (int32_t kx = -1; kx <= 1; ++kx) {
          int32_t iy = paddedY + ky;
          int32_t ix = paddedX + kx;
          float value = I[iy * paddedWidth + ix];
          float weight = W[(ky + 1) * 3 + (kx + 1)];
          sum += value * weight;
        }
      }
      O[y * width + x] = sum;
    }
  }
}


/*************************************************************
 *             命令行参数处理函数
 * -n size: 矩阵大小
*************************************************************/
int size = 32;

static void show_usage() {
  printf("Usage: [-n size] [-h: help]\n");
}

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
}

/*************************************************************
 *             OpenCL objects
*************************************************************/
cl_device_id device_id = NULL;
cl_context context = NULL;
cl_command_queue commandQueue = NULL;
cl_program program = NULL;
cl_kernel kernel = NULL;
cl_mem i_memobj = NULL;
cl_mem w_memobj = NULL;
cl_mem o_memobj = NULL;
uint8_t* kernel_bin = NULL;
/*************************************************************
 *             OpenCL 资源释放
*************************************************************/
static void cleanup() {
  if (commandQueue) clReleaseCommandQueue(commandQueue);
  if (kernel) clReleaseKernel(kernel);
  if (program) clReleaseProgram(program);
  if (i_memobj) clReleaseMemObject(i_memobj);
  if (w_memobj) clReleaseMemObject(w_memobj);
  if (o_memobj) clReleaseMemObject(o_memobj);
  if (context) clReleaseContext(context);
  if (device_id) clReleaseDevice(device_id);
  if (kernel_bin) free(kernel_bin);
}
/*************************************************************
 *            主程序框架很完整了
*************************************************************/
int main (int argc, char **argv) {
  // parse command arguments
  parse_args(argc, argv);

  printf("Matrix size=%d\n", size);

  uint32_t o_points = size * size;
  uint32_t i_points = (size+2) * (size+2);
  uint32_t w_points = 3 * 3;

/*************************************************************
 *            host 分配内存，生成输入数据 
*************************************************************/
  // Allocate memories for input arrays and output arrays.
  std::vector<float> h_i(i_points);
  std::vector<float> h_w(w_points);
  std::vector<float> h_o(o_points, 0.0f);

  // Generate input values
  for (int32_t y = -1; y < size+1; ++y) {
    for (int32_t x = -1; x < size+1; ++x) {
      if (x >= 0 && x < size && y >= 0 && y < size) {
        h_i[(y+1) * (size+2) + (x+1)] = static_cast<float>(rand()) / RAND_MAX;
      } else {
        h_i[(y+1) * (size+2) + (x+1)] = 0;
      }
    }
  }
  for (uint32_t i = 0; i < w_points; ++i) {
    h_w[i] = static_cast<float>(rand()) / RAND_MAX;
  }
  // 打印出来看一下
  printf("\n生成的输入数据\n");
  for (int32_t y = -1; y < size+1; ++y) {
    for (int32_t x = -1; x < size+1; ++x) {
      printf("%f ",h_i[(y+1) * (size+2) + (x+1)]);
    }
    printf("\n");
  }
  printf("生成的权重数据\n");
  for (uint32_t i = 0; i < 3; ++i) {
      for (uint32_t j = 0; j < 3; ++j) {
        printf("%f ",h_w[i*3+j]);
      }
      printf("\n");
  }
/*************************************************************
 *            opcencl program flow
*************************************************************/
  cl_platform_id platform_id;
  size_t kernel_size;

  // 1. Getting platform and device information
  CL_CHECK(clGetPlatformIDs(1, &platform_id, NULL));
  CL_CHECK(clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_DEFAULT, 1, &device_id, NULL));
  // 2. 创建上下文
  printf("Create context\n");
  context = CL_CHECK2(clCreateContext(NULL, 1, &device_id, NULL, NULL,  &_err));
  // 3. 获取设备信息
  char device_string[1024];
  clGetDeviceInfo(device_id, CL_DEVICE_NAME, sizeof(device_string), &device_string, NULL);
  printf("Using device: %s\n", device_string);
  // 4. 创建设备缓存
  printf("Allocate device buffers\n");
  size_t i_nbytes = i_points * sizeof(float);
  size_t w_nbytes = w_points * sizeof(float);
  size_t o_nbytes = o_points * sizeof(float);
  i_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, i_nbytes, NULL, &_err));
  w_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_READ_ONLY, w_nbytes, NULL, &_err));
  o_memobj = CL_CHECK2(clCreateBuffer(context, CL_MEM_WRITE_ONLY, o_nbytes, NULL, &_err));
  // 4. 读取kernel.cl 创建程序
  printf("Create program from kernel source\n");
  if (0 != read_kernel_file("kernel.cl", &kernel_bin, &kernel_size))
    return -1;
  program = CL_CHECK2(clCreateProgramWithSource(
    context, 1, (const char**)&kernel_bin, &kernel_size, &_err));
  if (program == NULL) {
    cleanup();
    return -1;
  }

  // 5. Build program
  CL_CHECK(clBuildProgram(program, 1, &device_id, NULL, NULL, NULL));

  // 6. Create kernel
  kernel = CL_CHECK2(clCreateKernel(program, KERNEL_NAME, &_err));

  // 7. Set kernel arguments
  CL_CHECK(clSetKernelArg(kernel, 0, sizeof(cl_mem), (void *)&o_memobj));
  CL_CHECK(clSetKernelArg(kernel, 1, sizeof(cl_mem), (void *)&i_memobj));
  CL_CHECK(clSetKernelArg(kernel, 2, sizeof(cl_mem), (void *)&w_memobj));
  CL_CHECK(clSetKernelArg(kernel, 3, sizeof(uint32_t), &size));
  CL_CHECK(clSetKernelArg(kernel, 4, sizeof(uint32_t), &size));

  // 8. Creating command queue   这一步也可以放到第四步之前，只需要有 context 和 device_id 就可以了
  commandQueue = CL_CHECK2(clCreateCommandQueue(context, device_id, 0, &_err));

  // 9. upload input data to device
	printf("Upload source buffers\n");
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, i_memobj, CL_TRUE, 0, i_nbytes, h_i.data(), 0, NULL, NULL));
  CL_CHECK(clEnqueueWriteBuffer(commandQueue, w_memobj, CL_TRUE, 0, w_nbytes, h_w.data(), 0, NULL, NULL));
  
  // 10. Execute the kernel; and measure the execution time
  size_t global_size[2] = {size, size};
  size_t local_size[2] = {1, 1};

  printf("Execute the kernel\n");
  auto time_start = std::chrono::high_resolution_clock::now();
  CL_CHECK(clEnqueueNDRangeKernel(commandQueue, kernel, 2, NULL, global_size, local_size, 0, NULL, NULL));
  CL_CHECK(clFinish(commandQueue));
  auto time_end = std::chrono::high_resolution_clock::now();
  double elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(time_end - time_start).count();
  printf("Elapsed time: %lg ms\n", elapsed);

  // 10. Download destination buffer from device to host
  printf("Download destination buffer\n");
  CL_CHECK(clEnqueueReadBuffer(commandQueue, o_memobj, CL_TRUE, 0, o_nbytes, h_o.data(), 0, NULL, NULL));

  // verify result in host
  printf("Verify result\n");
  std::vector<float> ref_vec(o_points);
  convolution_cpu(ref_vec.data(), h_i.data(), h_w.data(), size, size);
  int errors = 0;
  for (uint32_t i = 0; i < o_points; ++i) {
    if (!compare_equal(h_o[i], ref_vec[i])) {
      if (errors < 100)
        printf("*** error: [%d] expected=%f, actual=%f\n", i, ref_vec[i], h_o[i]);
      ++errors;
    }
  }
  if (errors != 0) {
    printf("FAILED! - %d errors\n", errors);
  } else {
    printf("PASSED!\n");
  }

  // lao
  printf("打印一下 CPU输出 和 vortex输出 \n");
  for (uint32_t i = 0; i < o_points; ++i) {
        printf("***  [%d]: expected=%f, actual=%f\n", i, ref_vec[i], h_o[i]);
  }

  // 11. Clean up
  cleanup();

  return errors;
}
