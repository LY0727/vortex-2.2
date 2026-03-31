import re

file_path = "syn/rtl_wjj/core/VX_execute.sv"

with open(file_path, "r") as f:
    content = f.read()

new_content = content.replace("`RESET_RELAY (alu_reset, reset);", """    VX_dispatch_if dispatch_if_alu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_alu   [`ISSUE_WIDTH]();
    VX_dispatch_if dispatch_if_lsu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_lsu   [`ISSUE_WIDTH]();
    VX_dispatch_if dispatch_if_sfu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_sfu   [`ISSUE_WIDTH]();
`ifdef EXT_F_ENABLE
    VX_dispatch_if dispatch_if_fpu [`ISSUE_WIDTH]();
    VX_commit_if   commit_if_fpu   [`ISSUE_WIDTH]();
`endif

    for (genvar i = 0; i < `ISSUE_WIDTH; i++) begin
        assign dispatch_if_alu[i].valid = dispatch_if[`EX_ALU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_alu[i].data  = dispatch_if[`EX_ALU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_ALU * `ISSUE_WIDTH + i].ready = dispatch_if_alu[i].ready;
        assign commit_if[`EX_ALU * `ISSUE_WIDTH + i].valid = commit_if_alu[i].valid;
        assign commit_if[`EX_ALU * `ISSUE_WIDTH + i].data  = commit_if_alu[i].data;
        assign commit_if_alu[i].ready = commit_if[`EX_ALU * `ISSUE_WIDTH + i].ready;

        assign dispatch_if_lsu[i].valid = dispatch_if[`EX_LSU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_lsu[i].data  = dispatch_if[`EX_LSU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_LSU * `ISSUE_WIDTH + i].ready = dispatch_if_lsu[i].ready;
        assign commit_if[`EX_LSU * `ISSUE_WIDTH + i].valid = commit_if_lsu[i].valid;
        assign commit_if[`EX_LSU * `ISSUE_WIDTH + i].data  = commit_if_lsu[i].data;
        assign commit_if_lsu[i].ready = commit_if[`EX_LSU * `ISSUE_WIDTH + i].ready;

        assign dispatch_if_sfu[i].valid = dispatch_if[`EX_SFU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_sfu[i].data  = dispatch_if[`EX_SFU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_SFU * `ISSUE_WIDTH + i].ready = dispatch_if_sfu[i].ready;
        assign commit_if[`EX_SFU * `ISSUE_WIDTH + i].valid = commit_if_sfu[i].valid;
        assign commit_if[`EX_SFU * `ISSUE_WIDTH + i].data  = commit_if_sfu[i].data;
        assign commit_if_sfu[i].ready = commit_if[`EX_SFU * `ISSUE_WIDTH + i].ready;
    end

`ifdef EXT_F_ENABLE
    for (genvar i = 0; i < `ISSUE_WIDTH; i++) begin
        assign dispatch_if_fpu[i].valid = dispatch_if[`EX_FPU * `ISSUE_WIDTH + i].valid;
        assign dispatch_if_fpu[i].data  = dispatch_if[`EX_FPU * `ISSUE_WIDTH + i].data;
        assign dispatch_if[`EX_FPU * `ISSUE_WIDTH + i].ready = dispatch_if_fpu[i].ready;
        assign commit_if[`EX_FPU * `ISSUE_WIDTH + i].valid = commit_if_fpu[i].valid;
        assign commit_if[`EX_FPU * `ISSUE_WIDTH + i].data  = commit_if_fpu[i].data;
        assign commit_if_fpu[i].ready = commit_if[`EX_FPU * `ISSUE_WIDTH + i].ready;
    end
`endif

    `RESET_RELAY (alu_reset, reset);""")

new_content = new_content.replace(".dispatch_if    (dispatch_if[`EX_ALU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".dispatch_if    (dispatch_if_alu),")
new_content = new_content.replace(".commit_if      (commit_if[`EX_ALU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".commit_if      (commit_if_alu),")

new_content = new_content.replace(".dispatch_if    (dispatch_if[`EX_LSU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".dispatch_if    (dispatch_if_lsu),")
new_content = new_content.replace(".commit_if      (commit_if[`EX_LSU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".commit_if      (commit_if_lsu),")

new_content = new_content.replace(".dispatch_if    (dispatch_if[`EX_FPU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".dispatch_if    (dispatch_if_fpu),")
new_content = new_content.replace(".commit_if      (commit_if[`EX_FPU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".commit_if      (commit_if_fpu),")

new_content = new_content.replace(".dispatch_if    (dispatch_if[`EX_SFU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".dispatch_if    (dispatch_if_sfu),")
new_content = new_content.replace(".commit_if      (commit_if[`EX_SFU * `ISSUE_WIDTH +: `ISSUE_WIDTH]),", ".commit_if      (commit_if_sfu),")

with open(file_path, "w") as f:
    f.write(new_content)

print(f"Patched {file_path}")
