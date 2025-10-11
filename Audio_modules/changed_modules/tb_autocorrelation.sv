`timescale 1ns/1ns

module tb_autocorrelation;

  // --- Parameters for simulation ---
  localparam W = 16;
  localparam N = 64; // Small, but enough for simulation
  localparam MIN_BPM = 60;
  localparam MAX_BPM = 120;
  localparam CLK_PERIOD = 20;

  // --- DUT I/O ---
  logic clk;
  logic reset;
  logic flux_valid;
  logic beat_valid;
  logic [W-1:0] flux_in;

  logic [15:0] BPM_estimate;
  logic bpm_valid;

  logic [1:0] state_out;

  // --- DUT instantiation ---
  autcorrelation #(
    .W(W),
    .N(N),
    .MIN_BPM(MIN_BPM),
    .MAX_BPM(MAX_BPM),
    .UPPER_LAG(800),   // ensure UPPER_LAG_FR is small enough for simulation
    .LOWER_LAG(300),
    .SAMPLE_RATE(12000),
    .FRAME_SIZE(1024),
    .STRIDE(1)
  ) dut (
    .clk(clk),
    .reset(reset),
    .flux_valid(flux_valid),
    .flux_in(flux_in),
    .beat_valid(beat_valid),
    .BPM_estimate(BPM_estimate),
    .bpm_valid(bpm_valid),
    .state_out(state_out)
  );

  // --- Clock ---
  initial clk = 0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // --- Stimulus ---
  initial begin
    reset = 1;
    flux_valid = 0;
    beat_valid = 0;
    flux_in = 0;

    #(CLK_PERIOD * 5);
    reset = 0;

    // --- Fill buffer with 64 samples ---
    repeat (70) begin
      @(posedge clk);
      flux_in = 16'd100 + $urandom_range(0, 10);
      flux_valid = 1;
      beat_valid = 0;
    end

    @(posedge clk);
    flux_valid = 1;
    beat_valid = 1; // only assert beat once to trigger FSM

    @(posedge clk);
    flux_valid = 0;
    beat_valid = 0;

    // Wait for FSM to run and output valid BPM
    repeat (500) @(posedge clk);

    $stop;
  end

  // --- Output Monitor ---
  initial begin
    $display("Time\tFlux\tBeat\tBPM\tValid\tState");
    forever begin
      @(posedge clk);
      $display("%0t\t%0d\t%b\t%0d\t%b\t%0d", 
        $time, flux_in, beat_valid, BPM_estimate, bpm_valid, state_out);
    end
  end

endmodule
