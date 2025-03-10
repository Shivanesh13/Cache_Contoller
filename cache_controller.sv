module cache_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter LINE_SIZE = 64,
    parameter NUM_SETS = 64,
    parameter ASSOCIATIVITY = 4,
    parameter OFFSET_WIDTH = $clog2(LINE_SIZE),
    parameter TAG_WIDTH = ADDR_WIDTH - $clog2(NUM_SETS) - $clog2(LINE_SIZE),
    parameter SETS_WIDTH = 6,
    parameter ASSOCIATIVITY_WIDTH = 2,
    parameter CACHE_SIZE = 16384
)(
    // Clock and reset
    input  logic clk,
    input  logic rst_n,
    
    // CPU interface
    input  logic [ADDR_WIDTH-1:0] cpu_addr,
    input  logic [DATA_WIDTH-1:0] cpu_write_data,
    output logic [DATA_WIDTH-1:0] cpu_read_data,
    input  logic cpu_read_en,
    input  logic cpu_write_en,
    output logic cpu_ready,
    
    // Memory interface
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic [LINE_SIZE*8-1:0] mem_write_data,
    input  logic [LINE_SIZE*8-1:0] mem_read_data,
    output logic mem_read_en,
    output logic mem_write_en,
    input  logic mem_ready
);

typedef enum reg [2:0] {IDLE,TAG_CHECK,MEM_UPDATE,WRITEBACK,FETCH,CACHE_READ} STATE;
STATE state,nxt_state;

logic [TAG_WIDTH-1:0] tag;
logic [$clog2(NUM_SETS)-1:0] index;
logic [$clog2(LINE_SIZE)-1:0] offset;

// Tag array signals
logic tag_read_en, tag_write_en,tag_hit,tag_dirty_bit;
logic [TAG_WIDTH-1:0] tag_id_in,tag_id_out;
logic [$clog2(NUM_SETS)-1:0] tag_index;
logic [ASSOCIATIVITY_WIDTH-1:0] tag_way,tag_hit_way,hit_way;


// Data cache signals
logic data_read_en, data_write_en,line_write_en,line_read_en;
logic [DATA_WIDTH-1:0] data_read_data;
logic [DATA_WIDTH-1:0] data_write_data;
logic [$clog2(NUM_SETS)-1:0] data_index;
logic [$clog2(ASSOCIATIVITY)-1:0] data_way,tag_miss_way;
logic [OFFSET_WIDTH-1:0] data_offset;
logic [LINE_SIZE*8-1:0] line_write_data, line_read_data;

tag_array #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .LINE_SIZE(LINE_SIZE),
    .NUM_SETS(NUM_SETS),
    .ASSOCIATIVITY(ASSOCIATIVITY)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .read_en(tag_read_en),
    .write_en(tag_write_en),
    .tag_in(tag_id_in),
    .index(tag_index),
    .way(tag_way),
    .hit(tag_hit),
    .hit_way(tag_hit_way),
    .miss_way(),
    .dirty_bit(tag_dirty_bit),
    .tag_out(tag_id_out)
);


data_array  data_cache_inst (
    .clk(clk),
    .rst_n(rst_n),
    .read_en(data_read_en),
    .write_en(data_write_en),
    .index(data_index),
    .way(data_way),
    .offset(data_offset),
    .write_data(data_write_data),
    .line_write_data(line_write_data),
    .read_data(data_read_data),
    .line_read_data(line_read_data),
    .line_write_en(line_write_en),
    .line_read_en(line_read_en)
);




assign {tag,index,offset} = (cpu_write_en || cpu_read_en) ? cpu_addr : {tag,index,offset};

logic op_type_write;
logic LRU_valid[0:NUM_SETS-1];
logic [1:0] LRU_hit_way[0:NUM_SETS-1];
logic [1:0] LRU_miss_way[0:NUM_SETS-1];
logic LRU_miss_req[0:NUM_SETS-1];

always_ff @(posedge clk) begin 
    if(!rst_n)begin
        state <= IDLE;
    end else begin
        state <= nxt_state;
    end
end

always_comb begin 
    // Default values
    nxt_state = state;
    cpu_ready = 1'b0;
    
    // Tag array controls
    tag_read_en = 1'b0;
    tag_write_en = 1'b0;
    tag_id_in = tag;
    tag_index = index;
    //tag_way = hit_way;
    
    // Data cache controls
    data_read_en = 1'b0;
    data_write_en = 1'b0;
    data_index = index;
    data_way = hit_way;
    data_offset = offset;
    data_write_data = cpu_write_data;
    line_write_data = mem_read_data;
    line_read_en = 1'b0;
    line_write_en = 1'b0;
    cpu_read_data = data_read_data;
    // Memory interface
    mem_addr = {tag, index, {OFFSET_WIDTH{1'b0}}};  // Aligned to cache line
    mem_write_data = line_read_data;
    mem_read_en = 1'b0;
    mem_write_en = 1'b0;
    LRU_valid[index] = 1'b0;
    LRU_hit_way[index] = 2'b0;
    if(LRU_miss_req[index])
        tag_miss_way = LRU_miss_way[index];
    else 
        tag_miss_way = tag_miss_way;
    LRU_miss_req[index] = 1'b0;

    case (state)
        IDLE: begin
            cpu_ready = 1'b1;
            op_type_write = 1'b0;
            if(cpu_write_en || cpu_read_en) begin
                nxt_state = TAG_CHECK;
                tag_read_en = 1'b1;
                tag_way = 'b0;
                if(cpu_write_en)
                    op_type_write = 1'b1;
            end else begin
                nxt_state = IDLE;
            end
        end
        TAG_CHECK : begin
            if(tag_hit) begin
                nxt_state = MEM_UPDATE;
                hit_way = tag_hit_way;
                LRU_valid[index] = 1'b1;
                LRU_hit_way[index] = tag_hit_way;
            end else begin
                LRU_miss_req[index] = 1'b1;
                if(tag_dirty_bit) begin
                    nxt_state = WRITEBACK;
                end else begin
                    nxt_state = FETCH;
                    mem_read_en = 1'b1;
                end
            end
        end
        MEM_UPDATE: begin
            if(!op_type_write) begin
                // Read hit
                data_read_en = 1'b1;
                data_way = hit_way;
                nxt_state = IDLE;
            end else begin
                // Write hit
                data_write_en = 1'b1;
                data_way = hit_way;
                
                // Update tag with dirty bit
                tag_write_en = 1'b1;
                tag_way = hit_way;
        
                nxt_state = IDLE;
            end
        end
        FETCH : begin
            mem_read_en = 1'b1;
            if(mem_ready) begin
                tag_write_en = 1'b1;
                tag_way = tag_miss_way;
                line_write_en = 'b1;
                data_way = tag_miss_way;

                if(op_type_write) begin
                    nxt_state = MEM_UPDATE;  
                    hit_way = tag_miss_way; 
                end else begin
                    nxt_state = CACHE_READ;
                end
            end
        end
        CACHE_READ : begin
            data_read_en = 1'b1;
            data_way = tag_miss_way;

            nxt_state = IDLE;
        end
        WRITEBACK: begin
            mem_write_en = 1'b1;
            line_read_en = 1'b1;
            if(mem_ready) begin
                //mem_write_en = 1'b0;
                nxt_state = FETCH;
            end
        end
        default: begin
            nxt_state = IDLE;
        end
    endcase
end


genvar i;
generate
    for(i = 0;i<NUM_SETS;i++) begin
        Tree_LRU u_tree_LRU_inst(
            .rst_n(rst_n),
            .clk(clk),
            .in_valid(LRU_valid[i]),
            .in_way(LRU_hit_way[i]),
            .out_req(LRU_miss_req[i]),
            .out_way(LRU_miss_way[i])
        );
    end
endgenerate


endmodule