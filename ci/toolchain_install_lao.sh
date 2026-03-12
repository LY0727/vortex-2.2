#!/bin/bash

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

# exit when any command fails
set -e

LOCAL_REPOSITORY=/mnt/ssd2/lao/vortex/build/vortex-toolchain-prebuilt-master
TOOLDIR=${TOOLDIR:=/mnt/ssd2/lao/vortex-tools}
OSVERSION=${OSVERSION:=ubuntu/focal}

# ubuntu/focal 
# 工具链名词、子目录、压缩包名
install_toolchain() {
    local toolchain=$1
    local subdir=$2
    local tarball=$3

    echo "Installing $toolchain from $LOCAL_REPOSITORY/$subdir/$tarball"
    tar -xvf $LOCAL_REPOSITORY/$subdir/$tarball
    mkdir -p $TOOLDIR && rm -rf $TOOLDIR/$toolchain && mv $toolchain $TOOLDIR
    rm -rf $toolchain $tarball
}

libcrt32() {
    install_toolchain "libcrt32" "libcrt32" "libcrt32.tar.bz2"
}

libcrt64() {
    install_toolchain "libcrt64" "libcrt64" "libcrt64.tar.bz2"
}

libc32() {
    install_toolchain "libc32" "libc32" "libc32.tar.bz2"
}

libc64() {
    install_toolchain "libc64" "libc64" "libc64.tar.bz2"
}

pocl() {
    install_toolchain "pocl" "pocl/$OSVERSION" "pocl2.tar.bz2"
}

verilator() {
    install_toolchain "verilator" "verilator/$OSVERSION" "verilator.tar.bz2"
}

sv2v() {
    install_toolchain "sv2v" "sv2v/$OSVERSION" "sv2v.tar.bz2"
}

#  压缩包路径： $LOCAL_REPOSITORY/$subdir/$tarball
llvm() {
    cat $LOCAL_REPOSITORY/llvm-vortex/$OSVERSION/llvm-vortex2.tar.bz2.part* > $LOCAL_REPOSITORY/llvm-vortex/llvm-vortex2.tar.bz2
    install_toolchain "llvm-vortex" "llvm-vortex" "llvm-vortex2.tar.bz2"
}
yosys() {
    cat $LOCAL_REPOSITORY/yosys/$OSVERSION/yosys.tar.bz2.part* > $LOCAL_REPOSITORY/yosys/yosys.tar.bz2
    install_toolchain "yosys" "yosys" "yosys.tar.bz2"
}
riscv32() {
    local parts=$(eval echo {a..k})
    echo $parts
    cat $LOCAL_REPOSITORY/riscv32-gnu-toolchain/$OSVERSION/riscv32-gnu-toolchain.tar.bz2.part* > $LOCAL_REPOSITORY/riscv32-gnu-toolchain/riscv32-gnu-toolchain.tar.bz2
    install_toolchain "riscv32-gnu-toolchain" "riscv32-gnu-toolchain" "riscv32-gnu-toolchain.tar.bz2"
}

riscv64() {
    local parts=$(eval echo {a..k})
    cat $LOCAL_REPOSITORY/riscv64-gnu-toolchain/$OSVERSION/riscv64-gnu-toolchain.tar.bz2.part* > $LOCAL_REPOSITORY/riscv64-gnu-toolchain/riscv64-gnu-toolchain.tar.bz2
    install_toolchain "riscv64-gnu-toolchain" "riscv64-gnu-toolchain" "riscv64-gnu-toolchain.tar.bz2"
}

show_usage()
{
    echo "Install Pre-built Vortex Toolchain"
    echo "Usage: $0 [--pocl] [--verilator] [--riscv32] [--riscv64] [--llvm] [--libcrt32] [--libcrt64] [--libc32] [--libc64] [--sv2v] [--yosys] [--all] [-h|--help]"
}

while [ "$1" != "" ]; do
    case $1 in
        --pocl ) pocl
                ;;
        --verilator ) verilator
                ;;
        --libcrt32 ) libcrt32
                ;;
        --libcrt64 ) libcrt64
                ;;
        --libc32 ) libc32
                ;;
        --libc64 ) libc64
                ;;
        --sv2v ) sv2v
                ;;
        --yosys ) yosys
                ;;
        --riscv32 ) riscv32
                ;;
        --riscv64 ) riscv64
                ;;
        --llvm ) llvm
                ;;
        --all ) pocl
                verilator
                libcrt32
                libcrt64
                libc32
                libc64
                llvm
                riscv32
                riscv64
                sv2v
                yosys
                ;;
        -h | --help ) show_usage
                exit
                ;;
        * ) show_usage
                exit 1
    esac
    shift
done