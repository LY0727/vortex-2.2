with open('libs/VX_pipe_register.sv', 'r') as f:
    content = f.read()

bad_str = """                localparam SLICE_END = SLICE_START + S_DATAW - 1;
                localparam S_DATAW = (i == NUM_SLICES-1) ? (DATAW - SLICE_START) : N_DATAW;"""

good_str = """                localparam S_DATAW = (i == NUM_SLICES-1) ? (DATAW - SLICE_START) : N_DATAW;
                localparam SLICE_END = SLICE_START + S_DATAW - 1;"""

content = content.replace(bad_str, good_str)

with open('libs/VX_pipe_register.sv', 'w') as f:
    f.write(content)

print("Fixed VX_pipe_register.sv")
