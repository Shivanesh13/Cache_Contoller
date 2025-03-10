`timescale 1ns/1ps

module tb_data_array;

    // Parameters
    parameter LINE_SIZE = 16;      // Smaller size for testbench (16 bytes)
    parameter NUM_SETS = 4;        // Smaller size for testbench
    parameter ASSOCIATIVITY = 2;   // Smaller size for testbench
    parameter DATA_WIDTH = 32;

    // Clock and reset
    logic clk = 0;
    logic rst_n;
    
    // Control signals
    logic read_en;
    logic write_en;
    logic [$clog2(NUM_SETS)-1:0] index;
    logic [$clog2(ASSOCIATIVITY)-1:0] way;
    logic [$clog2(LINE_SIZE)-1:0] offset;
    
    // Data signals
    logic [DATA_WIDTH-1:0] write_data;
    logic [LINE_SIZE*8-1:0] line_write_data;
    logic line_write_en;
    logic [DATA_WIDTH-1:0] read_data;
    logic [LINE_SIZE*8-1:0] line_read_data;
    logic line_read_en;
    logic [LINE_SIZE*8-1:0] expected_line = 0;
    logic [31:0] expected_word = {8'h8, 8'h7, 8'h6, 8'h5};
    
    // Clock generation (10ns period = 100MHz)
    always #5 clk = ~clk;

    // Instantiate the DUT
    data_array #(
        .LINE_SIZE(LINE_SIZE),
        .NUM_SETS(NUM_SETS),
        .ASSOCIATIVITY(ASSOCIATIVITY),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_en(read_en),
        .write_en(write_en),
        .index(index),
        .way(way),
        .offset(offset),
        .write_data(write_data),
        .line_write_data(line_write_data),
        .line_write_en(line_write_en),
        .read_data(read_data),
        .line_read_data(line_read_data),
        .line_read_en(line_read_en)
    );

    // Test stimulus
    initial begin
        // Initialize signals
        rst_n = 0;
        read_en = 0;
        write_en = 0;
        index = 0;
        way = 0;
        offset = 0;
        write_data = 0;
        line_write_data = 0;
        line_write_en = 0;
        line_read_en = 0;
        
        // Apply reset
        #20 rst_n = 1;
        
        // Test Case 1: Write a single word
        #10;
        $display("Test Case 1: Write a single word");
        index = 2;
        way = 1;
        offset = 8; // Start at offset 8
        write_data = 32'hABCD_1234;
        write_en = 1;
        #10 write_en = 0;
        
        // Test Case 2: Read back the word
        #10;
        $display("Test Case 2: Read back the word");
        read_en = 1;
        #10 read_en = 0;
        #10; // Extra cycle for WORD_READ state
        
        // Check the result
        if (read_data === 32'hABCD_1234)
            $display("PASS: Read data matches write data: %h", read_data);
        else
            $display("FAIL: Read data %h doesn't match expected %h", read_data, 32'hABCD_1234);
        
        // Test Case 3: Write a full line
        #10;
        $display("Test Case 3: Write a full line");
        index = 1;
        way = 0;
        
        // Initialize line with a pattern
        for (int i = 0; i < LINE_SIZE; i++) begin
            line_write_data[8*i +: 8] = i + 1; // 1, 2, 3, ...
        end
        
        line_write_en = 1;
        #10 line_write_en = 0;
        
        // Test Case 4: Read back the line
        #10;
        $display("Test Case 4: Read back the line");
        line_read_en = 1;
        #10 line_read_en = 0;
        #10; // Extra cycle for LINE_READ state
        
        // Check line data
        for (int i = 0; i < LINE_SIZE; i++) begin
            expected_line[8*i +: 8] = i + 1;
        end
        
        if (line_read_data === expected_line)
            $display("PASS: Line data matches expected pattern");
        else begin
            $display("FAIL: Line data doesn't match expected pattern");
            for (int i = 0; i < LINE_SIZE; i++) begin
                if (line_read_data[8*i +: 8] !== expected_line[8*i +: 8])
                    $display("  Byte %0d: Expected %h, Got %h", 
                             i, expected_line[8*i +: 8], line_read_data[8*i +: 8]);
            end
        end
        
        // Test Case 5: Verify way isolation
        #10;
        $display("Test Case 5: Verify way isolation");
        // Write to a different way in same set
        index = 1;
        way = 1;
        offset = 4;
        write_data = 32'h5555_AAAA;
        write_en = 1;
        #10 write_en = 0;
        
        // Read from original way
        way = 0;
        offset = 4;
        read_en = 1;
        #10 read_en = 0;
        #10; // Extra cycle for WORD_READ state
        
        // Expected data from our line pattern (bytes 5-8)
        if (read_data === expected_word)
            $display("PASS: Way isolation verified");
        else
            $display("FAIL: Way isolation failed. Expected %h, Got %h", expected_word, read_data);
        
        // End simulation
        #100 $display("Testbench completed");
        $finish;
    end
    
    // Optional: Monitor state transitions
    initial begin
        $monitor("Time %0t: State = %s", $time, 
                 (dut.state == 0) ? "IDLE" : 
                 (dut.state == 1) ? "WORD_READ" : 
                 (dut.state == 2) ? "LINE_READ" : "UNKNOWN");
    end

endmodule