interface VX_schedule_if ();
    typedef struct packed {
        logic [`UUID_WIDTH-1:0]     uuid;   
        logic [`NW_WIDTH-1:0]       wid;   
        logic [`NUM_THREADS-1:0]    tmask;
        logic [`PC_BITS-1:0]        PC;
    } data_t;
    logic  valid;
    data_t data;
    logic  ready;
    modport master (output valid,output data,input  ready);
    modport slave (input  valid,input  data,output ready);    
endinterface
