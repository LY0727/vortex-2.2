#!/bin/sh

# Copyright © 2019-2023
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ./ci/blackbox.sh --driver=xrt --app=conv3 --args=-n4  --debug=1 --log=run.log

show_usage()
{
    echo "Vortex BlackBox Test Driver v1.0"
    echo "Usage: $0 [[--clusters=#n] [--cores=#n] [--warps=#n] [--threads=#n] [--l2cache] [--l3cache] [[--driver=#name] [--app=#app] [--args=#args] [--debug=#level] [--scope] [--perf=#class] [--rebuild=#n] [--log=logfile] [--help]]"
}

show_help()
{
    show_usage
    echo "  where"
    echo "--driver: gpu, simx, rtlsim, oape, xrt"
    echo "--app: any subfolder test under regression or opencl"
    echo "--class: 0=disable, 1=pipeline, 2=memsys"
    echo "--rebuild: 0=disable, 1=force, 2=auto, 3=temp"
}
# root_dir 是 build/ci/.., 
# script_dir 是 build/ci
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$SCRIPT_DIR/..

DRIVER=rtlsim
APP=conv3
CLUSTERS=1
CORES=1
WARPS=4
THREADS=4
L2=
L3=
# 参数以DEBUG传入，传入数值实际为DEBUG_LEVEL
DEBUG=1
DEBUG_LEVEL=1
# SCOPE=1时，CORES=1 这个要求要细看scope模式的实现
SCOPE=0
# 是否有参数；参数是 --args=xxx 传入的；保存在ARGS变量中
HAS_ARGS=0
# 性能监控类别
PERF_CLASS=0
# 控制是否重建的变量
REBUILD=2
TEMPBUILD=0
# 日志文件名
LOGFILE=run.log
# 遍历参数
for i in "$@"
do
case $i in
    --driver=*)
        DRIVER=${i#*=}
        shift
        ;;
    --app=*)
        APP=${i#*=}
        shift
        ;;
    --clusters=*)
        CLUSTERS=${i#*=}
        shift
        ;;
    --cores=*)
        CORES=${i#*=}
        shift
        ;;
    --warps=*)
        WARPS=${i#*=}
        shift
        ;;
    --threads=*)
        THREADS=${i#*=}
        shift
        ;;
    --l2cache)
        L2=-DL2_ENABLE
        shift
        ;;
    --l3cache)
        L3=-DL3_ENABLE
        shift
        ;;
    --debug=*)
        DEBUG_LEVEL=${i#*=}
        DEBUG=1
        shift
        ;;
    --scope)
        SCOPE=1
        CORES=1
        shift
        ;;
    --perf=*)
        PERF_FLAG=-DPERF_ENABLE
        PERF_CLASS=${i#*=}
        shift
        ;;
    --args=*)
        ARGS=${i#*=}
        HAS_ARGS=1
        shift
        ;;
    --rebuild=*)
        REBUILD=${i#*=}
        shift
        ;;
    --log=*)
        LOGFILE=${i#*=}
        shift
        ;;
    --help)
        show_help
        exit 0
        ;;
    *)
        show_usage
        exit -1
        ;;
esac
done
# 如果REBUILD=3，那么REBUILD=1，TEMPBUILD=1
if [ $REBUILD -eq 3 ];
then
    REBUILD=1
    TEMPBUILD=1
fi
# 设置driver路径;注意这个驱动为gpu的情况
case $DRIVER in
    gpu)
        DRIVER_PATH=
        ;;
    simx)
        DRIVER_PATH=$ROOT_DIR/runtime/simx
        ;;
    rtlsim)
        DRIVER_PATH=$ROOT_DIR/runtime/rtlsim
        ;;
    opae)
        DRIVER_PATH=$ROOT_DIR/runtime/opae
        ;;
    xrt)
        DRIVER_PATH=$ROOT_DIR/runtime/xrt
        ;;
    *)
        echo "invalid driver: $DRIVER"
        exit -1
        ;;
esac
# 设置APP路径; 可以看到这里只支持opencl和regression两个文件夹
if [ -d "$ROOT_DIR/tests/opencl/$APP" ];
then
    APP_PATH=$ROOT_DIR/tests/opencl/$APP
elif [ -d "$ROOT_DIR/tests/regression/$APP" ];
then
    APP_PATH=$ROOT_DIR/tests/regression/$APP
else
    echo "Application folder not found: $APP"
    exit -1
fi
# drive为gpu时，直接运行APP; 其他情况下，需要先编译驱动，然后运行APP
# 这其实就是我之前直接在APP目录下运行make run-rtlsim的情况
# 如果有参数，在make时传递
if [ "$DRIVER" = "gpu" ];
then
    # running application
    if [ $HAS_ARGS -eq 1 ]
    then
        echo "running: OPTS=$ARGS make -C $APP_PATH run-$DRIVER"
        OPTS=$ARGS make -C $APP_PATH run-$DRIVER
        status=$?
    else
        echo "running: make -C $APP_PATH run-$DRIVER"
        make -C $APP_PATH run-$DRIVER
        status=$?
    fi

    exit $status
fi
# 这里的CONFIGS是一个特殊参数，是一个字符串，包含了所有的编译选项
# -D开头的是编译选项，传递-D后面的字符作为一个宏定义；这里就是能将 $CLUSTERS 的值作为一个宏定义 NUM_CLUSTERS 的值 传递给编译器或构建工具；
# 末尾的$CONFIGS 表示将此前可能定义了的 configs 选项保留下来； 也就是 累积配置 而不是 覆盖配置
CONFIGS="-DNUM_CLUSTERS=$CLUSTERS -DNUM_CORES=$CORES -DNUM_WARPS=$WARPS -DNUM_THREADS=$THREADS $L2 $L3 $PERF_FLAG $CONFIGS"

echo "CONFIGS=$CONFIGS"

# rebuild 标志不等于0 ； 是否要重建驱动器，调用runtime/driver下的makefile,再调用到sim/driver/ 下的makefile
if [ $REBUILD -ne 0 ]
then
    BLACKBOX_CACHE=blackbox.$DRIVER.cache
    if [ -f "$BLACKBOX_CACHE" ]
    then
        LAST_CONFIGS=`cat $BLACKBOX_CACHE` # 读取上次的配置，赋值给LAST_CONFIGS变量
    fi
    # 如果REBUILD=1 或者 配置发生了变化，那么清理驱动器; 将新的配置写入到缓存文件中，覆盖原有的配置
    if [ $REBUILD -eq 1 ] || [ "$CONFIGS+$DEBUG+$SCOPE" != "$LAST_CONFIGS" ];
    then
        make -C $DRIVER_PATH clean-driver > /dev/null
        echo "$CONFIGS+$DEBUG+$SCOPE" > $BLACKBOX_CACHE
    fi
fi

# export performance monitor class identifier
# runtime/stub 中有使用到这个环境变量
export VORTEX_PROFILING=$PERF_CLASS

status=0

# ensure config update   体现为两个头文件重新生成，按照新的硬件配置
make -C $ROOT_DIR/hw config > /dev/null

# ensure the stub driver is present  确保stub驱动器存在
make -C $ROOT_DIR/runtime/stub > /dev/null

# 这里是真正的运行部分,根据debug参数，输出日志或者不输出日志
# debug 不等于0 
if [ $DEBUG -ne 0 ]
then
    # running application
    if [ $TEMPBUILD -eq 1 ]
    then
        # setup temp directory
        TEMPDIR=$(mktemp -d)
        mkdir -p "$TEMPDIR/$DRIVER"

        # driver initialization
        if [ $SCOPE -eq 1 ]
        then
            echo "running: DESTDIR=$TEMPDIR/$DRIVER DEBUG=$DEBUG_LEVEL SCOPE=1 CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            DESTDIR="$TEMPDIR/$DRIVER" DEBUG=$DEBUG_LEVEL SCOPE=1 CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        else
            echo "running: DESTDIR=$TEMPDIR/$DRIVER DEBUG=$DEBUG_LEVEL CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            DESTDIR="$TEMPDIR/$DRIVER" DEBUG=$DEBUG_LEVEL CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        fi

        # running application
        if [ $HAS_ARGS -eq 1 ]
        then
            echo "running: VORTEX_RT_PATH=$TEMPDIR OPTS=$ARGS make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1"
            DEBUG=1 VORTEX_RT_PATH=$TEMPDIR OPTS=$ARGS make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1
            status=$?
        else
            echo "running: VORTEX_RT_PATH=$TEMPDIR make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1"
            DEBUG=1 VORTEX_RT_PATH=$TEMPDIR make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1
            status=$?
        fi

        # cleanup temp directory
        trap "rm -rf $TEMPDIR" EXIT
    else
        # driver initialization
        if [ $SCOPE -eq 1 ]
        then
            echo "running: DEBUG=$DEBUG_LEVEL SCOPE=1 CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            DEBUG=$DEBUG_LEVEL SCOPE=1 CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        else
            echo "running: DEBUG=$DEBUG_LEVEL CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            DEBUG=$DEBUG_LEVEL CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        fi

        # running application
        if [ $HAS_ARGS -eq 1 ]
        then
            echo "running: OPTS=$ARGS make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1"
            DEBUG=1 OPTS=$ARGS make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1
            status=$?
        else
            echo "running: make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1"
            DEBUG=1 make -C $APP_PATH run-$DRIVER > $LOGFILE 2>&1
            status=$?
        fi
    fi
    # 如果有trace.vcd文件，移动到当前目录
    if [ -f "$APP_PATH/trace.vcd" ]
    then
        mv -f $APP_PATH/trace.vcd .
    fi
# debug = 0; 不输出日志
else
    if [ $TEMPBUILD -eq 1 ]
    then
        # setup temp directory
        TEMPDIR=$(mktemp -d)
        mkdir -p "$TEMPDIR/$DRIVER"

        # driver initialization
        if [ $SCOPE -eq 1 ]
        then
            echo "running: DESTDIR=$TEMPDIR/$DRIVER SCOPE=1 CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            DESTDIR="$TEMPDIR/$DRIVER" SCOPE=1 CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        else
            echo "running: DESTDIR=$TEMPDIR/$DRIVER CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            DESTDIR="$TEMPDIR/$DRIVER" CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        fi

        # running application
        if [ $HAS_ARGS -eq 1 ]
        then
            echo "running: VORTEX_RT_PATH=$TEMPDIR OPTS=$ARGS make -C $APP_PATH run-$DRIVER"
            VORTEX_RT_PATH=$TEMPDIR OPTS=$ARGS make -C $APP_PATH run-$DRIVER
            status=$?
        else
            echo "running: VORTEX_RT_PATH=$TEMPDIR make -C $APP_PATH run-$DRIVER"
            VORTEX_RT_PATH=$TEMPDIR make -C $APP_PATH run-$DRIVER
            status=$?
        fi

        # cleanup temp directory
        trap "rm -rf $TEMPDIR" EXIT
    else

        # driver initialization
        if [ $SCOPE -eq 1 ]
        then
            echo "running: SCOPE=1 CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            SCOPE=1 CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        else
            echo "running: CONFIGS=$CONFIGS make -C $DRIVER_PATH"
            CONFIGS="$CONFIGS" make -C $DRIVER_PATH > /dev/null
        fi

        # running application
        if [ $HAS_ARGS -eq 1 ]
        then
            echo "running: OPTS=$ARGS make -C $APP_PATH run-$DRIVER"
            OPTS=$ARGS make -C $APP_PATH run-$DRIVER
            status=$?
        else
            echo "running: make -C $APP_PATH run-$DRIVER"
            make -C $APP_PATH run-$DRIVER
            status=$?
        fi
    fi
fi

exit $status
