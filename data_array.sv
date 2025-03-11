module data_array #(
    parameter LINE_SIZE = 64,  // In bytes
    parameter NUM_SETS = 64,
    parameter ASSOCIATIVITY = 4,
    parameter DATA_WIDTH = 32  // CPU data width
)(
    input  logic clk,
    input  logic rst_n,
    
    // Control signals
    input  logic read_en,
    input  logic write_en,
    input  logic [$clog2(NUM_SETS)-1:0] index,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] way,
    input  logic [$clog2(LINE_SIZE)-1:0] offset,
    
    // Data signals
    input  logic [DATA_WIDTH-1:0] write_data,
    input  logic [LINE_SIZE*8-1:0] line_write_data,  // For line fills
    input  logic line_write_en,  // Control for full line writes
    
    // Output signals
    output logic [DATA_WIDTH-1:0] read_data,
    output logic [LINE_SIZE*8-1:0] line_read_data,  // For writebacks
    input  logic line_read_en
);

typedef enum reg [1:0] {EMPTY,VALID,DIRTY} VAL_STATE;
typedef enum reg [1:0] {IDLE,WORD_READ,LINE_READ} DATA_STATE;

parameter BYTES_PER_WORD = DATA_WIDTH/8;

typedef struct packed {
    reg [LINE_SIZE-1:0][7:0] line_data;
} LINE_DATA;

typedef struct {
    LINE_DATA set_data[0:ASSOCIATIVITY-1];
} SET_DATA;


logic line_valid;
SET_DATA arr_data[0:NUM_SETS-1];
DATA_STATE state, nxt_state;
reg [LINE_SIZE-1:0][7:0] line_arr;
SET_DATA set_arr;

always_ff @(posedge clk) begin
    if(!rst_n) begin
        state <= IDLE;
    end
    else begin  
        state <= nxt_state;
    end
end 

always_comb begin 
    case (state)
        IDLE : begin
            if(!rst_n) begin
                nxt_state = IDLE;
                for(int i = 0;i < NUM_SETS; i++) begin
                    for(int j = 0;j < ASSOCIATIVITY; j++) begin
                        for(int k = 0; k < LINE_SIZE;k++) begin
                            arr_data[i].set_data[j].line_data[k] = '0;
                            line_arr[k] = '0;
                        end
                    end
                end
            end
            else if(read_en) begin
               line_arr = arr_data[index].set_data[way];
               nxt_state = WORD_READ;
            end else if(write_en) begin
                for(int i = 0;i<BYTES_PER_WORD;i++) begin
                    arr_data[index].set_data[way].line_data[offset + i] = write_data[8*i +: 8];
                end
                nxt_state = IDLE;
            end else if(line_write_en) begin
                for(int i=0;i<LINE_SIZE;i++) begin
                    arr_data[index].set_data[way].line_data[i] = line_write_data[8*i +: 8];       
                end
                nxt_state = IDLE;
            end else if(line_read_en) begin
                line_arr = arr_data[index].set_data[way];
                nxt_state = LINE_READ;
            end else begin
                nxt_state = IDLE;
            end
        end 
        WORD_READ : begin
            read_data = {line_arr[offset+3],line_arr[offset+2],line_arr[offset+1],line_arr[offset]};
            nxt_state = IDLE;
        end
        LINE_READ : begin
            for(int i=0;i<LINE_SIZE;i++) begin
                line_read_data[8*i +: 8] = line_arr[i];       
            end
           nxt_state = IDLE;
        end
    endcase
end

endmodule