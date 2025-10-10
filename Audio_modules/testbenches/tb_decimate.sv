`timescale 1ns/1ns
module tb_decimate;

    // Parameters
    localparam W = 16;
    localparam DECIMATE_FACTOR = 4;
    localparam CLK_PERIOD = 20;  

    // DUT I/O
    logic clk;
    logic reset;

    logic x_valid;
    logic x_ready;
    logic signed [W-1:0] x_data;

    logic y_valid;
    logic y_ready;
    logic signed [W-1:0] y_data;

    // Instantiate DUT
    decimation #(.W(W), .DECIMATE_FACTOR(DECIMATE_FACTOR)) dut (
        .clk(clk),
        .x_valid(x_valid),
        .x_ready(x_ready),
        .x_data(x_data),
        .y_valid(y_valid),
        .y_ready(y_ready),
        .y_data(y_data)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Sine Wave Generation
    real t = 0.0;
    real fs = 48000.0;  // Sample Rate - matches real-life input
    real freq_in = 4000.0;  // Sample Freq - higher than real-life for simulation purposes
    real step = 1.0/fs;
    int n;

    initial begin
        reset = 1;
        x_valid = 0;
        y_ready = 1; 
        #100 reset = 0;

        for (n = 0; n < 2000; n++) begin
            // Run sine wave on x_ready signal
            @(posedge clk);
            if (x_ready) begin
                t = n * step;
                x_data = $rtoi($sin(2.0 * 3.141592653 * freq_in * t) * ((1 << (W-1)) - 1)); //rtoi converts 'real' values for simulation
                x_valid = 1;
            end else begin
                x_valid = 0;
            end
        end

        #1000 $stop;
    end

endmodule

