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

// generic arbiter, can control multi hardware blocks' require
`include "VX_platform.vh"

`TRACING_OFF
module VX_generic_arbiter #(
    parameter NUM_REQS     = 1,
    parameter `STRING TYPE = "P",
    parameter LOG_NUM_REQS = `LOG2UP(NUM_REQS)
) (
    input  wire                     clk,
    input  wire                     reset,
    input  wire [NUM_REQS-1:0]      requests,
    output wire [LOG_NUM_REQS-1:0]  grant_index,
    output wire [NUM_REQS-1:0]      grant_onehot,
    output wire                     grant_valid,
    input  wire                     grant_ready
);
    if (TYPE == "P") begin

        `UNUSED_VAR (clk)
        `UNUSED_VAR (reset)
        `UNUSED_VAR (grant_ready)

        VX_priority_arbiter #( // priority arbiter, scheduling base on pre-assigned priorities
            .NUM_REQS (NUM_REQS)
        ) priority_arbiter (
            .requests     (requests),
            .grant_valid  (grant_valid),
            .grant_index  (grant_index),
            .grant_onehot (grant_onehot)
        );

    end else if (TYPE == "R") begin

        VX_rr_arbiter #( // round-robin arbiter, cyclic scheduling, but the start point will change based on the previous scheduling result
            .NUM_REQS (NUM_REQS)
        ) rr_arbiter (
            .clk          (clk),
            .reset        (reset),
            .requests     (requests),
            .grant_valid  (grant_valid),
            .grant_index  (grant_index),
            .grant_onehot (grant_onehot),
            .grant_ready  (grant_ready)
        );

    end else if (TYPE == "F") begin

        VX_fair_arbiter #( // fair arbiter, fair for all require
            .NUM_REQS (NUM_REQS)
        ) fair_arbiter (
            .clk          (clk),
            .reset        (reset),
            .requests     (requests),
            .grant_valid  (grant_valid),
            .grant_index  (grant_index),
            .grant_onehot (grant_onehot),
            .grant_ready  (grant_ready)
        );

    end else if (TYPE == "M") begin

        VX_matrix_arbiter #( // martix arbiter, allow multi require to access
            .NUM_REQS (NUM_REQS)
        ) matrix_arbiter (
            .clk          (clk),
            .reset        (reset),
            .requests     (requests),
            .grant_valid  (grant_valid),
            .grant_index  (grant_index),
            .grant_onehot (grant_onehot),
            .grant_ready  (grant_ready)
        );

    end else if (TYPE == "C") begin

        VX_cyclic_arbiter #( // cyclic arbiter, cyclic scheduling 
            .NUM_REQS (NUM_REQS)
        ) cyclic_arbiter (
            .clk          (clk),
            .reset        (reset),
            .requests     (requests),
            .grant_valid  (grant_valid),
            .grant_index  (grant_index),
            .grant_onehot (grant_onehot),
            .grant_ready  (grant_ready)
        );

    end else begin

        `ERROR(("invalid parameter"));

    end

endmodule
`TRACING_ON
