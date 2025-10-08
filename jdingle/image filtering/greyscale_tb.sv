// grayscale_tb.sv
`timescale 1ns/1ps

module grayscale_tb;

    parameter int IMG_SIZE = 1024; // adjust to the number of pixels in your .hex file
    logic clk;
    logic rst_n;

    // DUT signals
    logic in_valid;
    logic [23:0] pixel_in;
    logic out_valid;
    logic [7:0]  gray_out;

    // Memory for input and output
    reg [23:0] in_mem [0:IMG_SIZE-1];
    reg [7:0]  out_mem [0:IMG_SIZE-1];

    // Index counters
    int i;
    int write_idx;

    // Instantiate DUT
    grayscale_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .pixel_in(pixel_in),
        .out_valid(out_valid),
        .gray_out(gray_out)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz style (10ns period)

    // Load input file and run processing
    initial begin
        // Adjust path/names as needed:
        // 'in_image.hex' must contain IMG_SIZE lines (or fewer) of 24-bit hex words like: FF1122
        $readmemh("img.hex", in_mem);

        // Init
        rst_n = 0;
        in_valid = 0;
        pixel_in = 24'h0;
        write_idx = 0;
        #20;
        rst_n = 1;
        #10;

        // Process each pixel sequentially
        for (i = 0; i < IMG_SIZE; i++) begin
            pixel_in = in_mem[i];
            in_valid = 1'b1;
            @(posedge clk);
            in_valid = 1'b0; // assert one cycle
            // Wait one clock for out_valid (core asserts out_valid same cycle as in_valid in this simple design)
            @(posedge clk);
            if (out_valid) begin
                out_mem[write_idx] = gray_out;
                write_idx++;
            end else begin
                // No output? record 0 or handle pipeline latency
                out_mem[write_idx] = 8'h00;
                write_idx++;
            end
        end

        // Write results: only write used entries
        $display("Writing output image (%0d pixels) to out_image.hex ...", write_idx);
        // $writememh writes words; ensure we write bytes as two hex digits.
        // We'll make a temporary array of 8-bit regs and write it.
        // out_mem already is 8-bit reg array of size IMG_SIZE.
        $writememh("out_image.hex", out_mem, 0, write_idx-1);

        $display("Done. Sim end.");
        #20;
        $finish;
    end

endmodule
