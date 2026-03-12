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

`include "VX_define.vh"

interface VX_commit_csr_if ();

    wire [`PERF_CTR_BITS-1:0] instret;  // 用于统计提交的指令数，生产版本会被替换成 1 位的占位符

    modport master (
        output instret
    );

    modport slave (
        input instret
    );

endinterface
