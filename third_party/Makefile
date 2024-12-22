all: fpnew softfloat ramulator

fpn
# 编译得静态库 softfloat/build/Linux-x86_64-GCC/softfloat.a
softfloat:
	SPECIALIZE_TYPE=RISCV SOFTFLOAT_OPTS="-fPIC -DSOFTFLOAT_ROUND_ODD -DINLINE_LEVEL=5 -DSOFTFLOAT_FAST_DIV32TO16 -DSOFTFLOAT_FAST_DIV64TO32" $(MAKE) -C softfloat/build/Linux-x86_64-GCC
# 编译得动态库 ramulator/libramulator.so
ramulator/libramulator.so:
	cd ramulator && mkdir -p build && cd build && cmake .. && make -j4
ramulator: ramulator/libramulator.so

clean:
	$(MAKE) -C softfloat/build/Linux-x86_64-GCC clean
	rm -rf ramulator/build ramulator/libramulator.so

.PHONY: all fpnew softfloat ramulator