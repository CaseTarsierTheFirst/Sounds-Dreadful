`timescale 1ns/1ns
module decimate #(
    parameter W = 16,
    parameter DECIMATE_FACTOR = 4
)(
    input  logic clk,

    input  logic x_valid,
    output logic x_ready,
    input  logic [W-1:0] x_data,

    output logic y_valid,
    input  logic y_ready,
    output logic [W-1:0] y_data
);

    // Convolution output (always accepted)
    logic [2*W-1:0] conv_data;
    logic conv_valid;
    logic conv_ready;

    // Decimator internal counter
    logic [$clog2(DECIMATE_FACTOR)-1:0] dec_counter;

    // Capture convolution output in a register FIFO
    logic [2*W-1:0] conv_data_reg;
    logic conv_data_reg_valid;

    // Instantiate low-pass filter (32-bit fixed point)
    low_pass_conv #(
        .W(2*W),
        .W_FRAC(W)
    ) u_dec_filter (
        .clk(clk),
        .x_data({x_data, {W{1'b0}}}), // integer part in upper W bits
        .x_valid(x_valid),
        .x_ready(x_ready),
        .y_data(conv_data),
        .y_valid(conv_valid),
        .y_ready(1'b1) // always accept output
    );

    // Capture convolution result in register
    always_ff @(posedge clk) begin
        if (conv_valid) begin
            conv_data_reg <= conv_data;
            conv_data_reg_valid <= 1'b1;
        end else if (y_ready && y_valid) begin
            conv_data_reg_valid <= 1'b0; // downstream consumed
        end
    end

    // Downsample logic
    always_ff @(posedge clk) begin
        if (conv_data_reg_valid && (dec_counter == DECIMATE_FACTOR-1)) begin
            dec_counter <= 0;
        end else if (conv_data_reg_valid) begin
            dec_counter <= dec_counter + 1;
        end
    end

    // Output assignment
    assign y_data  = conv_data_reg[2*W-1:W]; // take integer part
    assign y_valid = conv_data_reg_valid && (dec_counter == DECIMATE_FACTOR-1);

endmodule
