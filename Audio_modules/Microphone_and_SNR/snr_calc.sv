// snr_calc.sv  (Quartus-safe, with reset)
// Estimates SNR in dB from mic_load samples and outputs an integer dB (0..255)

module snr_calc #(
  parameter int N = 16,
  parameter int EMA_SHIFT = 10   // averaging constant (2^10 ~ 1024 samples)
)(
  input  logic                clk,         // same domain as 'valid' (AUD_BCLK)
  input  logic                rst_n,       // active-high = run, low = reset
  input  logic                valid,       // 1-cycle strobe per new sample
  input  logic signed [N-1:0] sample_data, // mic_load.sample_data
  input  logic                KEY0,        // active-low: capture SNR noise ref
  output logic [7:0]          snr_db       // integer dB (floored at 0)
);

  // ---------------- 1) Power EMA (x^2 smoothed) ----------------
  logic [31:0] x2;
  always_ff @(posedge clk) begin
    if (!rst_n)              x2 <= '0;
    else if (valid)          x2 <= $signed(sample_data) * $signed(sample_data);
  end

  logic [47:0] pwr;
  always_ff @(posedge clk) begin
    if (!rst_n)              pwr <= '0;
    else if (valid)          pwr <= pwr - (pwr >> EMA_SHIFT) + {16'd0, x2};
  end

  // ---------------- 2) Noise floor capture (KEY0 active-low) ----------------
  logic btn0, btn1, btn_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      btn0 <= 1'b0; btn1 <= 1'b0; btn_q <= 1'b0;
    end else begin
      btn0 <= ~KEY0;           // high when pressed
      btn1 <= btn0;
      btn_q<= btn1;
    end
  end
  wire capture = btn1 & ~btn_q;

  logic [47:0] noise_pwr;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      noise_pwr <= 48'd1;
    end else begin
      if (capture)            noise_pwr <= (pwr == 0) ? 48'd1 : pwr; // avoid 0
      if (noise_pwr == 0)     noise_pwr <= 48'd1;
    end
  end

  // ---------------- 3) log2 approximation (Q8.8) ----------------
  function automatic [15:0] log2_q8 (input [47:0] v);
    int i;
    logic [7:0]  msb;           // 0..47
    int unsigned sh;            // UNSIGNED shift amount
    logic [47:0] norm;
    logic [7:0]  frac;
    begin
      if (v == 0) begin
        log2_q8 = 16'd0;
      end else begin
        msb = 8'd0;
        for (i = 47; i >= 0; i = i - 1)
          if (v[i]) begin msb = i[7:0]; break; end
        sh   = 47 - msb;
        norm = v << sh;         // normalize into [1,2)
        frac = norm[46:39];     // next 8 bits
        log2_q8 = {msb, frac};  // Q8.8
      end
    end
  endfunction

  // ---------------- 4) dB math: 10*log10(Ps/Pn) ~ 3.01*(log2Ps - log2Pn) ----------------
  logic [15:0] l2s, l2n, l2d, db_q8;
  logic [31:0] mult_tmp;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      l2s <= '0; l2n <= '0; l2d <= '0; mult_tmp <= '0; db_q8 <= '0;
    end else begin
      l2s      <= log2_q8(pwr);
      l2n      <= log2_q8(noise_pwr);
      l2d      <= l2s - l2n;
      mult_tmp <= l2d * 32'd773;     // ~*3.019
      db_q8    <= mult_tmp[23:8];    // >>8
    end
  end

  // ---------------- 5) Output: floor at 0, no 99-cap ----------------
  logic [7:0] db_i;
  always_comb begin
    db_i = db_q8[15:8];                 // integer part
    if ($signed(db_q8[15:8]) < 0)       snr_db = 8'd0;
    else                                 snr_db = db_i;   // up to 255
  end

endmodule
