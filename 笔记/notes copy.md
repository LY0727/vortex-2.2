## 1、官方仓库安装

**根据readme来；**

1. 安装配置

   1. clone;  这里之后都用 release 2.2

   ```
      git clone --depth=1 --recursive https://github.com/vortexgpgpu/vortex.git
      cd vortex
   	# 建议修改一下权限；中途遇到过不少权限问题，逐个修改太麻烦。
      chmod -R 755 /vortex-2.2
   ```

   2. 检查安装gcc 11
      ./ci/install_dependencies.sh
   3. mkdir build；  使用上面这句
      cd build
      ../configure --xlen=32 --tooldir=$HOME/tools

      ../configure --xlen=64 --tooldir=$HOME/tools
   4. 安装工具链，但是有时候网络也不太行；下载zip本地安装的话，需要理解一下脚本内容，自己写了一个压缩解压缩脚本。
      ./ci/toolchain_install.sh --all
   5. 三个额外的依赖：    注意依赖目录；ramulator需要clone release 2； clone后需要改文件夹名称，为 cvfpu;ramulator;softfloat;   或者改makefile也行
      cd ../third_party ；  `改makefile比较好，因为后续sim的makefile中是用fpnew的名字`
      git clone  git@github.com:ucb-bar/berkeley-softfloat-3.git
      git clone  git@github.com:CMU-SAFARI/ramulator2.git
      git clone  git@github.com:openhwgroup/cvfpu.git
      cd ../build
   6. 添加环境变量

      source ./ci/toolchain_env.sh

      echo "source `<build-path>`/ci/toolchain_env.sh" >> ~/.bashrc
   7. 编译
      make -s
   8. **安装目录修改：**  需要对应修改的文件有：

      1. toolchain_install.sh
      2. toolchain_env.sh
      3. config.mk
2. quick demo
   blackbox.sh脚本需要看一下；这里的命令是设置了cores，和测试项；还有一些默认配置在脚本中可见。

   ./ci/blackbox.sh --cores=2 --app=vecadd

   测试过程：

   1. 从命令的输出信息来看，主要是两个部分： runtime/simx 和 tests/opencl/vecadd     仿真器和测试应用程序。 两个目录下都有makefile
   2. 配置参数、编译运行时库simx和测试应用程序、进入测试目录、设置环境变量，执行测试程序。
   3. 具体测试程序、trace、输出结果还未研究。
3. 到这一步后建议阅读 docs/ 中的仿真文档
4. 通过makefile 来理解掌握整个工程。

## 2、个人仓库安装

问题一：

## 子模块仿真分析

**路径：** /mnt/ssd2/lao/vortex-2.2/build/hw/unittest/

1. makefile： 汇总调用6个子模块的makefile
2. common.mk:  verilator编译，生成波形，查看波形
3. subdir_dir下的makefile : 针对各个子模块；准备好相应的编译环境和编译选项，各种路径、编译标志和源文件列表等预备信息。**然后调用上层目录下的common.mk 进行verilator的仿真。**
