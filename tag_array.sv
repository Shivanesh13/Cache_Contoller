module tag_array#(
    parameter ADDR_WIDTH = 32,
    parameter LINE_SIZE = 64,
    parameter NUM_SETS = 64,
    parameter ASSOCIATIVITY = 4,
    parameter OFFSET_WIDTH = $clog2(LINE_SIZE),
    parameter TAG_WIDTH = ADDR_WIDTH - $clog2(NUM_SETS) - $clog2(LINE_SIZE),
    parameter SETS_WIDTH = 6,
    parameter ASSOCIATIVITY_WIDTH = 2
)(
    input  logic clk,
    input  logic rst_n,
    
    // Control signals
    input  logic read_en,
    input  logic write_en,
    input  logic [TAG_WIDTH-1:0] tag_in,
    input  logic [$clog2(NUM_SETS)-1:0] index,
    input  logic [$clog2(ASSOCIATIVITY)-1:0] way, // For writes
    
    
    // Output signals
    output logic hit,
    output logic [$clog2(ASSOCIATIVITY)-1:0] hit_way,
    output logic [$clog2(ASSOCIATIVITY)-1:0] miss_way,
    //output logic miss_dirtystate,
    output logic dirty_bit,
    output logic [TAG_WIDTH-1:0] tag_out
);

typedef enum reg [1:0] {EMPTY,VALID,DIRTY} VAL_STATE; 
typedef struct packed {
    VAL_STATE valid_state; // 0 
    reg [TAG_WIDTH-1:0] tag_id;
} TAG_LINE;
typedef TAG_LINE TAG_SET[0:ASSOCIATIVITY-1];
typedef TAG_SET TAG_ARRAY[0:NUM_SETS-1];


typedef enum reg [1:0] {IDLE,TAG_WRITE,TAG_READ} TAG_STATE;
TAG_STATE state,nxt_state;
TAG_ARRAY tag_arr;

logic [$clog2(NUM_SETS)-1:0] index_data;

TAG_SET tag_set;
logic tag_validate,tag_hit,tag_write,conflict;
logic [$clog2(ASSOCIATIVITY)-1:0] read_way,write_way;

// Single always_ff block that checks all ways
always_ff @(posedge clk) begin
    if(!rst_n) begin
        read_way <= '0;
        tag_hit <= '0;
        miss_way <= '0;
    end else if(tag_validate == 1'b1) begin
        // Default assignment
        read_way <= read_way; // Maintain current value
        tag_hit <= 'b0;
        // Check all ways
        for(int i = 0; i < ASSOCIATIVITY; i++) begin
            if(tag_set[i].tag_id == tag_in && 
               ((tag_set[i].valid_state == VALID) || (tag_set[i].valid_state == DIRTY))) begin
                read_way <= i;
                tag_hit <= 'b1;
            end
        end

    end else begin
        tag_hit <= 'b0;
        read_way <= 'b0;
    end
end

always_ff @(posedge clk) begin
    if(!rst_n)begin
        write_way <= 'b0;
        conflict <= 'b0;
    end else if(tag_write) begin
        write_way <= write_way;
        conflict <= 'b0;

        if(tag_set[way].valid_state == EMPTY) begin
            write_way <= way;
            conflict <= 1'b1;
        end else begin
            write_way <= way;
            conflict <= 1'b0;            
        end
        
    end else begin
        conflict <= 'b0;
    end
end


always_ff @(posedge clk) begin 
    if(!rst_n) begin
        for(int i = 0;i < NUM_SETS;i++) begin
            for(int j = 0; j < ASSOCIATIVITY;j++) begin
                tag_arr[i][j].tag_id <= '0;
                tag_arr[i][j].valid_state <= EMPTY;
            end
        end
    end else if(state == TAG_WRITE) begin
        if(conflict) begin
            tag_arr[index][write_way].tag_id = tag_in;
            tag_arr[index][write_way].valid_state = VALID; 
        end else begin
            tag_arr[index][write_way].tag_id = tag_in;
            tag_arr[index][write_way].valid_state = DIRTY;
        end
    end
end

always_ff @(posedge clk) begin
    if(!rst_n) begin
        state <= IDLE;
    end else begin
        state <= nxt_state;
    end
end

always_comb begin 
    case (state)
        IDLE : begin
            hit = 'b0;
            dirty_bit = 'b0;
            if(read_en) begin
                nxt_state = TAG_READ;
                tag_set = tag_arr[index];
                tag_validate = 1'b1;
            end else if(write_en) begin
                nxt_state = TAG_WRITE;
                tag_set = tag_arr[index];
                tag_write = 1'b1;
            end else begin
                tag_validate = 1'b0;
                tag_write = 1'b0;
                nxt_state = IDLE;
            end
        end 
        TAG_READ : begin
            tag_validate = 1'b0;
            tag_write = 1'b0;
            if(tag_hit) begin
                hit = 1'b1;
                hit_way = read_way;
                tag_out = tag_set[hit_way];
                if(tag_set[hit_way].valid_state == DIRTY) begin
                    dirty_bit = 1'b1;
                end else begin
                    dirty_bit = 1'b0;
                end
            end else begin
                hit = 1'b0;
                hit_way = 'b0;
                if(tag_set[way].valid_state == DIRTY) begin
                    dirty_bit = 1'b1;
                end else begin
                    dirty_bit = 1'b0;
                end
            end
            nxt_state = IDLE;
        end
        TAG_WRITE : begin
            tag_validate = 1'b0;
            tag_write = 1'b0;

            nxt_state = IDLE;
        end

    endcase
end

endmodule