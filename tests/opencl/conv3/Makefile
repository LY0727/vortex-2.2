ROOT_DIR := $(realpath ../../..)
include $(ROOT_DIR)/config.mk

PROJECT := conv3

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := $(SRC_DIR)/main.cc

# 复制到build/test/opencl/conv3/目录下
kernel.cl: $(SRC_DIR)/kernel.cl
	cp $< $@

KERNEL_SRCS := kernel.cl

# 传入参数，这里是卷积的 输入方阵的 长宽
OPTS ?= -n32

include ../common.mk
