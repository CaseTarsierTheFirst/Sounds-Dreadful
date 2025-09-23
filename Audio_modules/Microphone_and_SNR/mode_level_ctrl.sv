// mode_level_ctrl.sv  (Quartus-safe, fully declared)
// Two modes: 0=SNR (passes snr_db_in), 1=dBA_rel (ambient-captured reference).
// KEY1 (active-low): capture ambient & enter dBA mode
// KEY2 (active-low): reset dBA ref and return to SNR mode

module mode_level_ctrl #(
  parameter int N = 16,
  parameter int EMA_SHIFT = 10,
  parameter int CAL_OFFSET_DB = 20   // simple calibration offset for dBA_rel
)(
  input  logic                clk,          // AUD_BCLK domain
  input  logic                rst_n,        // active-high = run, low = reset
  input  logic                samp_valid,   // 1-cycle strobe per sample
  input  logic signed [N-1:0] sample_data,  // from mic_load
  input  logic                KEY1,         // active-low: capture & enter dBA
  input  logic                KEY2,         // active-low: reset to SNR
  input  logic [7:0]          snr_db_in,    // SNR to show in SNR mode
  output logic [7:0]          disp_db,      // what to display (SNR or dBA)
  output logic                mode_is_dba   // 0=SNR, 1=dBA mode
);

  // --- Power EMA of squared samples ---
  logic [31:0] x2;
  logic [47:0] pwr;

  always_ff @(posedge clk) begin
    if (!rst_n)                    x2 <= '0;
    else if (samp_valid)           x2 <= $signed(sample_data) * $signed(sample_data);
  end

  always_ff @(posedge clk) begin
    if (!rst_n)                    pwr <= '0;
    else if (samp_valid)           pwr <= pwr - (pwr >> EMA_SHIFT) + {16'd0, x2};
  end

  // --- Button sync / edge detect (active-low -> high on press) ---
  logic b1_0, b1_1, b1_q;
  logic b2_0, b2_1, b2_q;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      b1_0 <= 1'b0; b1_1 <= 1'b0; b1_q <= 1'b0;
      b2_0 <= 1'b0; b2_1 <= 1'b0; b2_q <= 1'b0;
    end else begin
      b1_0 <= ~KEY1;  b1_1 <= b1_0;  b1_q <= b1_1;
      b2_0 <= ~KEY2;  b2_1 <= b2_0;  b2_q <= b2_1;
    end
  end

  wire press1 = b1_1 & ~b1_q;  // KEY1 press
  wire press2 = b2_1 & ~b2_q;  // KEY2 press

  // --- Mode and dBA reference handling ---
  logic [47:0] dba_ref;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mode_is_dba <= 1'b0;
      dba_ref     <= 48'd1;
    end else if (press2) begin
      mode_is_dba <= 1'b0;          // back to SNR
      dba_ref     <= 48'd1;         // clear ref (avoid zero)
    end else if (press1) begin
      mode_is_dba <= 1'b1;          // enter dBA mode
      dba_ref     <= (pwr == 0) ? 48'd1 : pwr;
    end
  end

  // --- log2 approximation (Q8.8), Quartus-safe ---
  function automatic [15:0] log2_q8 (input [47:0] v);
    int i;
    logic [7:0]  msb;
    int unsigned sh;        // unsigned to avoid shift warning
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
        norm = v << sh;
        frac = norm[46:39];
        log2_q8 = {msb, frac};
      end
    end
  endfunction

  // --- dBA_rel = 10*log10(P/P_ref) ≈ 3.019*(log2(P)-log2(P_ref)) + CAL_OFFSET_DB ---
  logic [15:0] l2P, l2R, l2D, db_q8;
  logic [31:0] mult_tmp;
  logic [7:0]  dba_db;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      l2P <= '0; l2R <= '0; l2D <= '0; mult_tmp <= '0; db_q8 <= '0;
    end else begin
      l2P      <= log2_q8(pwr);
      l2R      <= log2_q8(dba_ref);
      l2D      <= l2P - l2R;
      mult_tmp <= l2D * 32'd773;     // ~*3.019
      db_q8    <= mult_tmp[23:8];
    end
  end

  // *** FIXED: declare dba_i outside, assign inside ***
  int signed dba_i;  // moved out of always_comb

  always_comb begin
    dba_i = $signed(db_q8[15:8]) + CAL_OFFSET_DB; // apply offset
    if (dba_i < 0)        dba_db = 8'd0;
    else if (dba_i > 255) dba_db = 8'd255;
    else                  dba_db = dba_i[7:0];
  end

  // --- Output mux ---
  always_comb begin
    disp_db = mode_is_dba ? dba_db : snr_db_in;
  end

endmodule
