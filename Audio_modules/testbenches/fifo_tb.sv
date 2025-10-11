//tb_fft_input_buffer

//ModelSim will NOT run FIFO.v - have to simulate this functionality unfortunately as I have already spent about 2 hours on it
//Below is a simulated fifo that works pretty much the same

module fifo #(parameter W=16, DEPTH=32) (
    input  logic        aclr,
    input  logic        wrclk,
    input  logic        wrreq,
    input logic signed [W-1:0] data,
    output logic        wrfull,

    input  logic        rdclk,
    input  logic        rdreq,
    output logic signed [W-1:0] q,
    output logic        rdfull
);

    logic signed [W-1:0] mem [0:DEPTH-1];
    int wr_ptr, rd_ptr;
    int wr_count, rd_count; // two counters - one for each clock

	 //Writing
    always_ff @(posedge wrclk or posedge aclr) begin
        if (aclr) begin
            wr_ptr <= 0;
            wr_count <= 0;
        end else if (wrreq && (wr_count - rd_count) < DEPTH) begin
            mem[wr_ptr] <= data;
            wr_ptr <= (wr_ptr+1) % DEPTH;
            wr_count <= wr_count + 1;
        end
    end

	 //Reading
    always_ff @(posedge rdclk or posedge aclr) begin
        if (aclr) begin
            rd_ptr <= 0;
            rd_count <= 0;
            q <= '0;
        end else if (rdreq && (wr_count - rd_count) > 0) begin
            q <= mem[rd_ptr];
            rd_ptr <= (rd_ptr+1) % DEPTH;
            rd_count <= rd_count + 1;
        end
    end

    //output flags
    assign wrfull  = ((wr_count - rd_count) == DEPTH);
    assign rdfull  = ((wr_count - rd_count) != 0);

endmodule


//Testbench for FIFO

`timescale 1ns/1ns
module tb_fft_input_buffer;

    localparam W = 16;
    localparam NSamples = 32;
    localparam CLK_PERIOD = 20;
    localparam AUDIO_CLK_PERIOD = 1000;

    logic clk;
    logic reset;
    logic audio_clock;
    logic audio_input_valid;
    logic audio_input_ready;
    logic signed [W-1:0] audio_input_data;
    logic signed [W-1:0] fft_input;
    logic fft_input_valid;

    // Instantiate DUT
    fft_input_buffer #(.W(W), .NSamples(NSamples)) dut (
        .clk(clk),
        .reset(reset),
        .audio_clk(audio_clock),
        .audio_input_valid(audio_input_valid),
        .audio_input_ready(audio_input_ready),
        .audio_input_data(audio_input_data),
        .fft_input(fft_input),
        .fft_input_valid(fft_input_valid)
    );

    // Clock generation
    initial clk = 0;
    initial audio_clock = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    always #(AUDIO_CLK_PERIOD/2) audio_clock = ~audio_clock;

    // Sine wave input
    real t = 0.0;
    real fs = 12000.0;
    real freq_in = 4000.0;
    real step = 1.0/fs;
    int n = 0;

    initial begin
        reset = 1;
        audio_input_valid = 0;
        #200 reset = 0;
        #5000000 $stop;
    end

    always @(posedge audio_clock) begin
        if (!reset && audio_input_ready) begin
            t = n * step;
            audio_input_data = $rtoi($sin(2*3.141592653*freq_in*t) * ((1<<(W-1))-1));
            audio_input_valid = 1;
            n = n + 1;
            $display("Pushed sample: %d", audio_input_data);
        end else begin
            audio_input_valid = 0;
        end
    end

    // Monitor FFT output
    always @(posedge clk) begin
        if (fft_input_valid) begin
            $display("FFT input: %d", fft_input);
        end
    end

endmodule
