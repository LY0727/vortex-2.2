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

`include "VX_platform.vh"

`TRACING_OFF

/*================================================================================
 * VX_elastic_buffer     vld-rdy握手协议的弹性缓冲区模块
 *
模块参数 (Parameters)
    1.DATAW: 数据位宽，默认为 1。
    2.SIZE: 缓冲区的深度（可以容纳的数据个数），默认为 1。不同的深度会触发不同的底层实现。
    3.OUT_REG: 控制输出端是否需要寄存器打拍。（0 表示无额外寄存，1 或 2 可能对应单拍/全带宽寄存，通常用于优化时序）。
    4.LUTRAM: 布尔类型/标志为。当缓冲区较大需要使用 FIFO 时，指示综合工具是否优先使用分布式 RAM (LUTRAM) 而不是块 RAM (Block RAM)。
    5.MAX_FANOUT: 最大扇出限制。用于在数据位宽极大时，将数据切片以减轻布线拥塞和时序压力，默认为 0（不作扇出限制）。

功能模式：
    1. SIZE == 0 (直通模式)
    2. MAX_FANOUT != 0 且数据宽度较大 (扇出切片优化)
        当 DATAW 大于允许的安全扇出阈值时，会将整个数据总线切分成多个小片段 (NUM_SLICES)。通过 for 循环，针对每个片段递归例化较窄的 VX_elastic_buffer。
        这主要是为了解决超宽数据总线（例如 512 位、1024 位）中 valid/ready 控制信号驱动过多寄存器而导致的高扇出时序违例 (Timing Violation) 问题。
        只有片段 0 的握手信号对上下游可见，其他片段随片段 0 同步。
    3.SIZE == 1 (单级流水线)  (默认模式)
        例化 VX_pipe_buffer。适用于只需要打一拍，深度为 1 的场景。
    4.SIZE == 2 && LUTRAM == 0 (双级 Skid Buffer)
        例化 VX_skid_buffer。Skid Buffer（防滑缓冲区）是一种经典设计，
        它既能像寄存器一样切断组合逻辑关键路径（完全解耦 ready 和 valid），又不会损失流水线带宽。
        深度为 2 是 Skid Buffer 的典型大小。不在乎 RAM 资源 (LUTRAM=0) 时优选此逻辑门的实现。
    5.SIZE > 2 或其他情况 (通用 FIFO 结构)
        例化一个基于 RAM 或寄存器堆的通用深度的 FIFO VX_fifo_queue。
        在这之后还串联了一个 VX_pipe_buffer（根据 OUT_REG 参数配置深度），
        以便在增加一层缓存的同时，进一步改善末端的时序（改善 output clock-to-q 延迟）。
 *===========================================================================*/

module VX_elastic_buffer #(
    parameter DATAW   = 1,
    parameter SIZE    = 1,
    parameter OUT_REG = 0,
    parameter LUTRAM  = 0,
    parameter MAX_FANOUT = 0
) (
    input  wire             clk,
    input  wire             reset,

    input  wire             valid_in,
    output wire             ready_in,
    input  wire [DATAW-1:0] data_in,

    output wire [DATAW-1:0] data_out,
    input  wire             ready_out,
    output wire             valid_out
);
    if (SIZE == 0) begin

        `UNUSED_VAR (clk)
        `UNUSED_VAR (reset)

        assign valid_out = valid_in;
        assign data_out  = data_in;
        assign ready_in  = ready_out;

    end else if (MAX_FANOUT != 0 && (DATAW > (MAX_FANOUT + MAX_FANOUT/2))) begin

        localparam NUM_SLICES = `CDIV(DATAW, MAX_FANOUT);
        localparam N_DATAW = DATAW / NUM_SLICES;

        for (genvar i = 0; i < NUM_SLICES; ++i) begin

            localparam S_DATAW = (i == NUM_SLICES-1) ? (DATAW - i * N_DATAW) : N_DATAW;

            wire valid_out_t, ready_in_t;
            `UNUSED_VAR (valid_out_t)
            `UNUSED_VAR (ready_in_t)

            `RESET_RELAY (slice_reset, reset);

            VX_elastic_buffer #(
                .DATAW   (S_DATAW),
                .SIZE    (SIZE),
                .OUT_REG (OUT_REG),
                .LUTRAM  (LUTRAM)
                ) buffer_slice (
                .clk       (clk),
                .reset     (slice_reset),
                .valid_in  (valid_in),
                .data_in   (data_in[i * N_DATAW +: S_DATAW]),
                .ready_in  (ready_in_t),
                .valid_out (valid_out_t),
                .data_out  (data_out[i * N_DATAW +: S_DATAW]),
                .ready_out (ready_out)
            );

            if (i == 0) begin
                assign ready_in = ready_in_t;
                assign valid_out = valid_out_t;
            end
        end

    end else if (SIZE == 1) begin

        VX_pipe_buffer #(
            .DATAW (DATAW)
        ) pipe_buffer (
            .clk       (clk),
            .reset     (reset),
            .valid_in  (valid_in),
            .data_in   (data_in),
            .ready_in  (ready_in),
            .valid_out (valid_out),
            .data_out  (data_out),
            .ready_out (ready_out)
        );

    end else if (SIZE == 2 && LUTRAM == 0) begin

        VX_skid_buffer #(
            .DATAW   (DATAW),
            .HALF_BW (OUT_REG == 2),
            .OUT_REG (OUT_REG)
        ) skid_buffer (
            .clk       (clk),
            .reset     (reset),
            .valid_in  (valid_in),
            .data_in   (data_in),
            .ready_in  (ready_in),
            .valid_out (valid_out),
            .data_out  (data_out),
            .ready_out (ready_out)
        );

    end else begin

        wire empty, full;

        wire [DATAW-1:0] data_out_t;
        wire ready_out_t;

        wire push = valid_in && ready_in;
        wire pop = ~empty && ready_out_t;

        VX_fifo_queue #(
            .DATAW   (DATAW),
            .DEPTH   (SIZE),
            .OUT_REG (OUT_REG == 1),
            .LUTRAM  (LUTRAM)
        ) fifo_queue (
            .clk    (clk),
            .reset  (reset),
            .push   (push),
            .pop    (pop),
            .data_in(data_in),
            .data_out(data_out_t),
            .empty  (empty),
            .full   (full),
            `UNUSED_PIN (alm_empty),
            `UNUSED_PIN (alm_full),
            `UNUSED_PIN (size)
        );

        assign ready_in = ~full;

        VX_pipe_buffer #(
            .DATAW (DATAW),
            .DEPTH ((OUT_REG > 0) ? (OUT_REG-1) : 0)
        ) out_buf (
            .clk       (clk),
            .reset     (reset),
            .valid_in  (~empty),
            .data_in   (data_out_t),
            .ready_in  (ready_out_t),
            .valid_out (valid_out),
            .data_out  (data_out),
            .ready_out (ready_out)
        );

    end

endmodule
`TRACING_ON
