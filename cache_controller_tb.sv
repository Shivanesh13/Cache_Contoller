`timescale 1ns/1ps

module cache_controller_tb();
    // Parameters
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam LINE_SIZE = 64;
    localparam NUM_SETS = 64;
    localparam ASSOCIATIVITY = 4;
    localparam OFFSET_WIDTH = $clog2(LINE_SIZE);
    localparam TAG_WIDTH = ADDR_WIDTH - $clog2(NUM_SETS) - $clog2(LINE_SIZE);
    localparam CACHE_SIZE = 16384;
    
    // Clock and reset
    logic clk;
    logic rst_n;
    
    // CPU interface
    logic [ADDR_WIDTH-1:0] cpu_addr;
    logic [DATA_WIDTH-1:0] cpu_write_data;
    logic [DATA_WIDTH-1:0] cpu_read_data;
    logic cpu_read_en;
    logic cpu_write_en;
    logic cpu_ready;
    
    // Memory interface
    logic [ADDR_WIDTH-1:0] mem_addr;
    logic [LINE_SIZE*8-1:0] mem_write_data;
    logic [LINE_SIZE*8-1:0] mem_read_data;
    logic mem_read_en;
    logic mem_write_en;
    logic mem_ready;
    
    // Test reporting
    int test_count = 0;
    int pass_count = 0;
    
    // Instantiate the DUT
    cache_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .LINE_SIZE(LINE_SIZE),
        .NUM_SETS(NUM_SETS),
        .ASSOCIATIVITY(ASSOCIATIVITY),
        .CACHE_SIZE(CACHE_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_write_data(cpu_write_data),
        .cpu_read_data(cpu_read_data),
        .cpu_read_en(cpu_read_en),
        .cpu_write_en(cpu_write_en),
        .cpu_ready(cpu_ready),
        .mem_addr(mem_addr),
        .mem_write_data(mem_write_data),
        .mem_read_data(mem_read_data),
        .mem_read_en(mem_read_en),
        .mem_write_en(mem_write_en),
        .mem_ready(mem_ready)
    );
    
    // Memory model
    logic [DATA_WIDTH-1:0] memory[0:1023];
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Memory response logic
    always @(posedge clk) begin
        if (mem_read_en) begin
            // Delay memory response by a few cycles
            //repeat(1) @(posedge clk);
            
            // Fill the cache line with sequential data based on address
            for (int i = 0; i < LINE_SIZE / 4; i++) begin
                automatic int addr_offset = mem_addr[ADDR_WIDTH-1:2] + i;
                mem_read_data[i*32 +: 32] = {addr_offset[15:0], addr_offset[15:0]};
            end
            mem_ready <= 1'b1;
        end else if (mem_write_en) begin
            // Delay memory response by a few cycles
            //repeat(1) @(posedge clk);
            
            // Store the data (if this was a real system)
            // Here we're just acknowledging the write
            mem_ready <= 1'b1;
        end else begin
            mem_ready <= 1'b0;
        end
    end
    
    // Test tasks
    task reset_system();
        rst_n = 0;
        cpu_addr = 0;
        cpu_write_data = 0;
        cpu_read_en = 0;
        cpu_write_en = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
    endtask
    
    task cpu_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        $display("CPU Write: Address = 0x%h, Data = 0x%h", addr, data);
        
        // Wait for cache to be ready before starting a new operation
        wait_for_cpu_ready();
        
        // Start the write operation
        cpu_addr = addr;
        cpu_write_data = data;
        cpu_write_en = 1'b1;
        cpu_read_en = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        cpu_write_en = 1'b0;
        
        // Wait for operation to complete
        wait_for_cpu_ready();
        
        // Allow some settling time
        repeat(2) @(posedge clk);
    endtask
    
    task cpu_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
        $display("CPU Read: Address = 0x%h", addr);
        
        // Wait for cache to be ready before starting a new operation
        wait_for_cpu_ready();
        
        // Start the read operation
        cpu_addr = addr;
        cpu_read_en = 1'b1;
        cpu_write_en = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        cpu_read_en = 1'b0;
        // Wait for operation to complete
        wait_for_cpu_ready();
        
        
        // Capture the data
        data = cpu_read_data;
        $display("CPU Read Result: Data = 0x%h", data);
        
        // Allow some settling time
        repeat(2) @(posedge clk);
    endtask
    
    task wait_for_cpu_ready();
        automatic int timeout_counter = 0;
        while (!cpu_ready && timeout_counter < 1000) begin
            @(posedge clk);
            timeout_counter++;
        end
        
        if (timeout_counter >= 1000) begin
            $display("ERROR: Timeout waiting for cpu_ready signal");
            $finish;
        end
    endtask
    
    task check_result(string test_name, logic [DATA_WIDTH-1:0] actual, logic [DATA_WIDTH-1:0] expected);
        test_count++;
        if (actual === expected) begin
            pass_count++;
            $display("PASS: %s - Got: 0x%h, Expected: 0x%h", test_name, actual, expected);
        end else begin
            $display("FAIL: %s - Got: 0x%h, Expected: 0x%h", test_name, actual, expected);
        end
    endtask
    
    // Main testbench flow
    initial begin
        $display("Starting Cache Controller Testbench");
        
        // Initialize and reset
        reset_system();
        
        // Test 1: Cache miss followed by a hit (read)
        begin
            automatic logic [DATA_WIDTH-1:0] read_data;
            automatic logic [ADDR_WIDTH-1:0] addr = 32'h0000_1000;
            automatic logic [DATA_WIDTH-1:0] expected_data;
            
            // First read - should be a miss
            cpu_read(addr, read_data);
            
            // Expected data based on our memory model
            expected_data = {16'h0400, 16'h0400};  // addr >> 2 = 0x400
            check_result("First Read (Cache Miss)", read_data, expected_data);
            
            // Second read to same address - should be a hit
            cpu_read(addr, read_data);
            check_result("Second Read (Cache Hit)", read_data, expected_data);
        end
        
        // Test 2: Write followed by read to same address
        begin
            automatic logic [DATA_WIDTH-1:0] read_data;
            automatic logic [ADDR_WIDTH-1:0] addr = 32'h0000_2000;
            automatic logic [DATA_WIDTH-1:0] write_data = 32'hDEAD_BEEF;
            
            // Write to cache
            cpu_write(addr, write_data);
            
            // Read from same address
            cpu_read(addr, read_data);
            check_result("Read After Write", read_data, write_data);
        end
        
        // Test 3: Multiple addresses in same cache line
        begin
            automatic logic [DATA_WIDTH-1:0] read_data;
            automatic logic [ADDR_WIDTH-1:0] base_addr = 32'h0000_3000;
            
            // Write to first word in cache line
            cpu_write(base_addr, 32'h1111_1111);
            
            // Write to second word in cache line
            cpu_write(base_addr + 4, 32'h2222_2222);
            
            // Read both words back
            cpu_read(base_addr, read_data);
            check_result("Read First Word in Line", read_data, 32'h1111_1111);
            
            cpu_read(base_addr + 4, read_data);
            check_result("Read Second Word in Line", read_data, 32'h2222_2222);
        end
        
        // Test 4: Cache eviction
        begin
            automatic logic [DATA_WIDTH-1:0] read_data;
            automatic logic [ADDR_WIDTH-1:0] addr1 = 32'h0000_4000;
            automatic logic [ADDR_WIDTH-1:0] addr2 = 32'h0001_4000;  // Different tag, same index
            automatic logic [ADDR_WIDTH-1:0] addr3 = 32'h0001_5000;  // Different tag, same index
            automatic logic [ADDR_WIDTH-1:0] addr4 = 32'h0001_6000;  // Different tag, same index
            automatic logic [DATA_WIDTH-1:0] expected_data;
            
            // Write to first address
            cpu_write(addr1, 32'hAAAA_AAAA);
            
            // Write to second address (should evict the first)
            cpu_write(addr2, 32'hBBBB_BBBB);
            cpu_write(addr3, 32'hBBBB_CCCC);
            cpu_write(addr4, 32'hCCCC_BBBB);
            
            cpu_read(addr4, read_data);
            check_result("Read After Eviction (addr2)", read_data, 32'hCCCC_BBBB);
            
            cpu_read(addr3, read_data);
            check_result("Read After Eviction (addr2)", read_data, 32'hBBBB_CCCC);
            

            // Read from second address
            cpu_read(addr2, read_data);
            check_result("Read After Eviction (addr2)", read_data, 32'hBBBB_BBBB);
            
            // Read from first address (should be a miss, and data should be reloaded)
            cpu_read(addr1, read_data);
            
            // Without knowing the exact replacement policy, we just check if we get any valid response
            expected_data = 32'hAAAA_AAAA;  // We use the actual data written previously
            check_result("Read After Eviction (addr1 - reloaded)", read_data, expected_data);
        end
        
        // Test 5: Consecutive Reads to Different Addresses
        begin
            automatic logic [DATA_WIDTH-1:0] read_data1, read_data2;
            automatic logic [ADDR_WIDTH-1:0] addr1 = 32'h0000_5000;
            automatic logic [ADDR_WIDTH-1:0] addr2 = 32'h0000_6000;
            automatic logic [DATA_WIDTH-1:0] expected_data1, expected_data2;
            
            // First read - will be a miss
            cpu_read(addr1, read_data1);
            
            // Second read to different address - will also be a miss
            cpu_read(addr2, read_data2);
            
            // Expected data based on our memory model
            expected_data1 = {16'h1400, 16'h1400};  // addr1 >> 2 = 0x1400
            expected_data2 = {16'h1800, 16'h1800};  // addr2 >> 2 = 0x1800
            
            check_result("Sequential Read 1", read_data1, expected_data1);
            check_result("Sequential Read 2", read_data2, expected_data2);
        end
        
        // /Test 6: Consecutive Writes to Different Addresses
        begin
            automatic logic [DATA_WIDTH-1:0] read_data;
            automatic logic [ADDR_WIDTH-1:0] addr1 = 32'h0000_7000;
            automatic logic [ADDR_WIDTH-1:0] addr2 = 32'h0000_8000;
            
            // Write to first address
            cpu_write(addr1, 32'hCCCC_CCCC);
            
            // Write to second address
            cpu_write(addr2, 32'hDDDD_DDDD);
            
            // Read back both addresses
            cpu_read(addr1, read_data);
            check_result("Consecutive Write-Read 1", read_data, 32'hCCCC_CCCC);
            
            cpu_read(addr2, read_data);
            check_result("Consecutive Write-Read 2", read_data, 32'hDDDD_DDDD);
        end
        
        // Test Summary
        $display("\n=== Test Summary ===");
        $display("Tests: %0d, Passed: %0d, Failed: %0d", 
                 test_count, pass_count, test_count - pass_count);
        
        if (pass_count == test_count)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
            
        $finish;
    end
    
    // Optional: Timeout to prevent infinite loops
    initial begin
        #100000;  // 100,000 ns = 100 μs
        $display("Timeout reached - simulation terminated");
        $finish;
    end
    
endmodule