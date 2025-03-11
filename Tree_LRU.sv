module Tree_LRU (
    input logic clk,         // Added clock
    input logic rst_n,
    input logic in_valid,    // Fixed missing semicolon
    input logic [1:0] in_way,
    input logic out_req,     // Consistent type declaration
    output logic [1:0] out_way
);

    // Tree bits (need to be registered)
    logic root, left, right;

    // Victim way selection (combinational)
    always_comb begin 
        if (!rst_n) begin
            out_way = 2'b00;
        end else if (out_req) begin
            // Follow tree bits to find LRU way
            if (root == 1'b0) begin
                if (right == 1'b0) out_way = 2'b11;
                else out_way = 2'b10;
            end else begin
                if (left == 1'b0) out_way = 2'b01;
                else out_way = 2'b00;
            end
        end else begin
            out_way = out_way; // Default value when not requesting
        end
    end

    // Tree bit updates (sequential)
    always_ff @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            // Reset tree bits
            root <= 1'b0;
            left <= 1'b0;
            right <= 1'b0;
        end else if (in_valid) begin
            // Update tree bits when accessing a way
            // Set bits to point AWAY from accessed way
            case (in_way)
                2'b00: begin
                    root <= 1'b0;  // Point to right subtree
                    left <= 1'b0;  // Point to way 01
                end 
                2'b01: begin
                    root <= 1'b0;  // Point to right subtree
                    left <= 1'b1;  // Point to way 00
                end
                2'b10: begin
                    root <= 1'b1;  // Point to left subtree
                    right <= 1'b0; // Point to way 11
                end 
                2'b11: begin
                    root <= 1'b1;  // Point to left subtree
                    right <= 1'b1; // Point to way 10
                end
                default: begin
                    // No change for invalid ways
                end
            endcase
        end else if (out_req) begin
            // Update tree bits when accessing a way
            // Set bits to point AWAY from accessed way
            case (out_way)
                2'b00: begin
                    root <= 1'b0;  // Point to right subtree
                    left <= 1'b0;  // Point to way 01
                end 
                2'b01: begin
                    root <= 1'b0;  // Point to right subtree
                    left <= 1'b1;  // Point to way 00
                end
                2'b10: begin
                    root <= 1'b1;  // Point to left subtree
                    right <= 1'b0; // Point to way 11
                end 
                2'b11: begin
                    root <= 1'b1;  // Point to left subtree
                    right <= 1'b1; // Point to way 10
                end
                default: begin
                    // No change for invalid ways
                end
            endcase
        end
    end
    
endmodule