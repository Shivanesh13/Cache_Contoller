`timescale 1ns/1ps

module tag_array_test();
    // Parameters
    parameter ADDR_WIDTH = 32;
    parameter LINE_SIZE = 64;
    parameter NUM_SETS = 64;
    parameter ASSOCIATIVITY = 4;
    parameter OFFSET_WIDTH = $clog2(LINE_SIZE);
    parameter TAG_WIDTH = ADDR_WIDTH - $clog2(NUM_SETS) - $clog2(LINE_SIZE);
    parameter SETS_WIDTH = 6;
    parameter ASSOCIATIVITY_WIDTH = 2;
    
    // DUT signals
    logic clk;
    logic rst_n;
    
    // Control signals
    logic read_en;
    logic write_en;
    logic [TAG_WIDTH-1:0] tag_in;
    logic [$clog2(NUM_SETS)-1:0] index;
    logic [$clog2(ASSOCIATIVITY)-1:0] way;
    
    // Output signals
    logic hit;
    logic [$clog2(ASSOCIATIVITY)-1:0] hit_way;
    logic [$clog2(ASSOCIATIVITY)-1:0] miss_way;
    logic dirty_bit;
    logic [TAG_WIDTH-1:0] tag_out [ASSOCIATIVITY-1:0];
    
    // Test counters
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // Instantiate DUT
    tag_array #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_SIZE(LINE_SIZE),
        .NUM_SETS(NUM_SETS),
        .ASSOCIATIVITY(ASSOCIATIVITY)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_en(read_en),
        .write_en(write_en),
        .tag_in(tag_in),
        .index(index),
        .way(way),
        .hit(hit),
        .hit_way(hit_way),
        .miss_way(miss_way),
        .dirty_bit(dirty_bit),
        .tag_out(tag_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Task for checking results
    task check_result(string test_name, logic expected_hit, logic [$clog2(ASSOCIATIVITY)-1:0] expected_way = '0, 
                     logic expected_dirty = 0);
        test_count++;
        if ((hit === expected_hit) && 
            (!expected_hit || (hit_way === expected_way)) && 
            (dirty_bit === expected_dirty)) begin
            $display("[PASS] %s", test_name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", test_name);
            $display("  Expected: hit=%b, hit_way=%h, dirty=%b", expected_hit, expected_way, expected_dirty);
            $display("  Actual:   hit=%b, hit_way=%h, dirty=%b", hit, hit_way, dirty_bit);
            fail_count++;
        end
    endtask
    
    // Reset task
    task reset_dut();
        rst_n = 0;
        read_en = 0;
        write_en = 0;
        tag_in = 0;
        index = 0;
        way = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask
    
    // Task to write a tag entry
    task write_tag(logic [TAG_WIDTH-1:0] tag, logic [$clog2(NUM_SETS)-1:0] set_idx, 
                  logic [$clog2(ASSOCIATIVITY)-1:0] way_idx);
        @(posedge clk);
        write_en = 1;
        read_en = 0;
        tag_in = tag;
        index = set_idx;
        way = way_idx;
        @(posedge clk);
        write_en = 0;
        @(posedge clk); // Wait for operation to complete
    endtask
    
    // Task to read a tag
    task read_tag(logic [TAG_WIDTH-1:0] tag, logic [$clog2(NUM_SETS)-1:0] set_idx);
        @(posedge clk);
        write_en = 0;
        read_en = 1;
        tag_in = tag;
        index = set_idx;
        @(posedge clk);
        read_en = 0;
        @(posedge clk); // Wait for operation to complete
    endtask
    
    // Main test sequence
    initial begin
        $display("Starting tag_array testbench...");
        
        // Reset the DUT
        reset_dut();
        
        // Test 1: Write to way 0, then read back (hit expected)
        $display("\nTest 1: Basic write and read hit");
        write_tag(24'hABCDEF, 6'h05, 2'h0);
        read_tag(24'hABCDEF, 6'h05);
        check_result("Test 1: Basic hit check", 1'b1, 2'h0, 1'b0);
        
        // Test 2: Read a non-existent tag (miss expected)
        $display("\nTest 2: Read miss test");
        read_tag(24'h123456, 6'h05);
        check_result("Test 2: Miss check", 1'b0, 2'h0, 1'b0);
        
        // Test 3: Write multiple ways in same set, then read back
        $display("\nTest 3: Multiple ways in same set");
        write_tag(24'h111111, 6'h0A, 2'h0);
        write_tag(24'h222222, 6'h0A, 2'h1);
        write_tag(24'h333333, 6'h0A, 2'h2);
        write_tag(24'h444444, 6'h0A, 2'h3);
        
        read_tag(24'h111111, 6'h0A);
        check_result("Test 3a: Way 0 hit check", 1'b1, 2'h0, 1'b0);
        
        read_tag(24'h222222, 6'h0A);
        check_result("Test 3b: Way 1 hit check", 1'b1, 2'h1, 1'b0);
        
        read_tag(24'h333333, 6'h0A);
        check_result("Test 3c: Way 2 hit check", 1'b1, 2'h2, 1'b0);
        
        read_tag(24'h444444, 6'h0A);
        check_result("Test 3d: Way 3 hit check", 1'b1, 2'h3, 1'b0);
        
        // Test 4: Dirty bit test (overwrite an entry)
        $display("\nTest 4: Dirty bit handling");
        // First write creates VALID state
        write_tag(24'hAAAA, 6'h20, 2'h1);
        // Second write to same way creates DIRTY state
        write_tag(24'hBBBB, 6'h20, 2'h1);
        
        // Check if we get a dirty eviction signal when trying to replace
        write_en = 0;
        read_en = 1;
        tag_in = 24'hCCCC;
        index = 6'h20;
        way = 2'h1;
        @(posedge clk);
        read_en = 0;
        @(posedge clk);
        // In your current implementation, the dirty bit should be set when trying to evict
        check_result("Test 4: Dirty eviction check", 1'b0, 2'h0, 1'b1);
        
        // Test 5: Different sets don't interfere
        $display("\nTest 5: Set independence test");
        write_tag(24'hAA5555, 6'h3F, 2'h2); // Last set
        read_tag(24'hAA5555, 6'h3F);
        check_result("Test 5a: Last set hit check", 1'b1, 2'h2, 1'b0);
        
        read_tag(24'hAA5555, 6'h0); // First set, same tag
        check_result("Test 5b: First set miss check", 1'b0, 2'h0, 1'b0);
        
        // Test 6: Verify state transition
        $display("\nTest 6: State transition verification");
        // Read a previously written tag
        read_tag(24'hBBBB, 6'h20);
        check_result("Test 6: Read dirty entry", 1'b1, 2'h1, 1'b0);
        
        // Report test results
        $display("\nTest Summary:");
        $display("  Total tests: %0d", test_count);
        $display("  Passed: %0d", pass_count);
        $display("  Failed: %0d", fail_count);
        
        if (fail_count == 0)
            $display("\nAll tests passed!");
        else
            $display("\nSome tests failed!");
            
        $finish;
    end
    
    // Monitor signals
    initial begin
        $monitor("Time=%0t: state=%s, read_en=%b, write_en=%b, tag_in=%h, index=%h, way=%h, hit=%b, hit_way=%h, dirty_bit=%b",
                 $time, dut.state.name(), read_en, write_en, tag_in, index, way, hit, hit_way, dirty_bit);
    end
    
endmodule