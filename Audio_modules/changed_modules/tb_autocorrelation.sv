`timescale 1ns/1ns
module tb_autocorrelation;

  localparam W = 16;
  localparam N = 64;
  localparam CLK_PERIOD = 20;

  logic clk, reset;
  logic flux_valid;
  logic beat_valid;
  logic [W-1:0] flux_in;

  logic [15:0] BPM_estimate;
  logic bpm_valid;
  logic [1:0] state_out;

  autcorrelation #(
    .W(W),
    .N(N),
    .UPPER_LAG(800),
    .LOWER_LAG(300),
    .MIN_BPM(60),
    .MAX_BPM(120)
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

  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    reset = 1;
    flux_valid = 0;
    beat_valid = 0;
    flux_in = 0;

    #(5 * CLK_PERIOD);
    reset = 0;

    // Feed a bunch of flux samples
    repeat (100) begin
      @(posedge clk);
      flux_in = 100 + $urandom_range(0, 20);
      flux_valid = 1;
      // Make beat_valid true at some times
      beat_valid = (flux_in > 110);
      @(posedge clk);
      flux_valid = 0;
      beat_valid = 0;
    end

    // Wait some cycles for FSM to complete
    repeat (200) @(posedge clk);

    $display("Final BPM_estimate: %0d, bpm_valid: %b", BPM_estimate, bpm_valid);
    $stop;
  end

  initial begin
    $display("Time\tFlux\tBeat\tState\tBPM\tbpm_valid");
    forever begin
      @(posedge clk);
      $display("%0t\t%0d\t%b\t%0d\t%0d\t%b",
        $time, flux_in, beat_valid, state_out, BPM_estimate, bpm_valid);
    end
  end

endmodule
