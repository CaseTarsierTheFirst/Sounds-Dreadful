// fft_mag_sq.sv (fixed)
// Computes |Re|^2 + |Im|^2 with 2-cycle pipeline and a matched valid strobe.
module fft_mag_sq #(
  parameter int W = 16  // FFT input half-width; FFT outputs are 2*W
)(
  input  logic                   clk,
  input  logic                   reset,
  input  logic                   fft_valid,                 // 1-cycle enable from FFT
  input  logic signed [2*W-1:0]  fft_real,                  // FFT do_re
  input  logic signed [2*W-1:0]  fft_imag,                  // FFT do_im
  output logic        [4*W-1:0]  mag_sq,                    // |Re|^2 + |Im|^2
  output logic                   mag_valid                  // 1-cycle strobe with mag_sq
);

  // Stage 1: square (treat as unsigned after squaring)
  logic [4*W-1:0] re2, im2;
  logic           v1;
  always_ff @(posedge clk) begin
    if (reset) begin
      re2 <= '0; im2 <= '0; v1 <= 1'b0;
    end else begin
      // Squaring a signed value yields a non-negative result -> use unsigned width 4W
      re2 <= $signed(fft_real) * $signed(fft_real);
      im2 <= $signed(fft_imag) * $signed(fft_imag);
      v1  <= fft_valid;
    end
  end

  // Stage 2: add
  logic [4*W-1:0] sum2;
  logic           v2;
  always_ff @(posedge clk) begin
    if (reset) begin
      sum2 <= '0; v2 <= 1'b0;
    end else begin
      sum2 <= re2 + im2;
      v2   <= v1;
    end
  end

  // Outputs aligned with v2
  always_ff @(posedge clk) begin
    if (reset) begin
      mag_sq    <= '0;
      mag_valid <= 1'b0;
    end else begin
      mag_sq    <= sum2;
      mag_valid <= v2;
    end
  end
endmodule
