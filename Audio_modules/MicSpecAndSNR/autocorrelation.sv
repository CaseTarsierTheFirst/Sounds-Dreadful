module autocorrelation #(
    parameter int N            = 1024,   // history depth
    parameter int W            = 70,     // flux input width
    parameter int MIN_BPM      = 40,
    parameter int MAX_BPM      = 240,    // >=220 lets lag=3 → 200 BPM reachable
    // legacy (kept):
    parameter int LOWER_LAG    = 2400,
    parameter int UPPER_LAG    = 12000,
    parameter int LAG_RANGE    = UPPER_LAG - LOWER_LAG + 1,
    parameter int LAG_WIDTH    = 14,
    parameter int SAMPLE_RATE  = 12000,  // Hz
    parameter int FRAME_SIZE   = 1024,   // must match hop
    parameter int STRIDE       = 1,      // hop stride in frames
    parameter int CORR_W       = 18,     // MAC width (LSBs of flux)
    parameter int REFINE_FRAC_BITS = 3,  // fractional step = 1/2^bits (default 1/8)

    // --- Post-filter knobs ---
    parameter int SMOOTH_SHIFT     = 3,  // EMA strength: 1/2^k per update
    parameter int LOCK_PCT_SHIFT   = 5,  // lock window ≈ previous ±(1/2^k)
    parameter int SLEW_MAX_BPM     = 4   // limit bpm change per update
)(
    input  logic              clk,
    input  logic              reset,
    input  logic              flux_valid,
    input  logic [W-1:0]      flux_in,
    input  logic              beat_valid,

    output logic [15:0]       BPM_estimate,
    output logic              bpm_valid,

    output logic [1:0]        state_out
);

  // ---------------- exact lag bounds (avoid FPS truncation) ------------------
  function automatic int ceil_div32(input int unsigned a, input int unsigned b);
    ceil_div32 = (a + b - 1) / b;
  endfunction
  localparam int unsigned DENOM_BASE = FRAME_SIZE * STRIDE;
  localparam int LOWER_LAG_FR = ceil_div32(60*SAMPLE_RATE, MAX_BPM * DENOM_BASE);
  localparam int UPPER_LAG_FR =          (60*SAMPLE_RATE) / (MIN_BPM * DENOM_BASE);

  // -------- widths --------
  localparam int AW   = $clog2(N);
  localparam int JW   = AW;
  localparam int LW   = $clog2((UPPER_LAG_FR>0)?(UPPER_LAG_FR+1):2);
  localparam int ACCW = 2*CORR_W + JW + 2;
  localparam int IW   = CORR_W;
  localparam int M_FRAC_STEPS = (1 << REFINE_FRAC_BITS);

  // -------- history RAM --------
  (* ramstyle = "M10K, no_rw_check" *) logic [W-1:0] ram [0:N-1];

  logic [AW-1:0] wr_ptr;
  logic [AW:0]   valid_count;
  logic [15:0]   stride_cnt;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      wr_ptr      <= '0;
      valid_count <= '0;
      stride_cnt  <= '0;
    end else if (flux_valid) begin
      if (stride_cnt == STRIDE-1) stride_cnt <= '0; else stride_cnt <= stride_cnt + 1'b1;
      if (stride_cnt == 0) begin
        ram[wr_ptr] <= flux_in;
        wr_ptr      <= wr_ptr + 1'b1;
        if (valid_count != N) valid_count <= valid_count + 1'b1;
      end
    end
  end

  function automatic [AW-1:0] age_to_addr(input [AW:0] age);
    logic [AW:0] tmp;  tmp = {1'b0,wr_ptr} - 1'b1 - age;  age_to_addr = tmp[AW-1:0];
  endfunction
  function automatic [CORR_W-1:0] take_corr(input [W-1:0] x);
    take_corr = x[CORR_W-1:0];
  endfunction

  // Start latch (only on a beat)
  logic start_req;
  always_ff @(posedge clk or posedge reset) begin
    if (reset) start_req <= 1'b0;
    else begin
      if (flux_valid && beat_valid && (valid_count > (UPPER_LAG_FR + 2))) start_req <= 1'b1;
      if (state_out == 2'b00 && start_req) start_req <= 1'b0;
    end
  end

  // -------- FSM (integer sweep + fractional refinement) --------
  typedef enum logic [2:0] { IDLE, ACC_ADDR, ACC_MAC, LAG_ADV, REF_INIT, REF_ADDR0, REF_ADDR1, REF_MAC } state_t;
  state_t state;  assign state_out = state[1:0];

  // indices
  logic [LW-1:0]  lag_index;
  logic [JW-1:0]  j_index, j_index_ref;
  logic [AW:0]    j_limit, j_limit_ref;
  logic           last_iter, last_iter_s;

  // RAM read
  logic [AW-1:0]  rd_addr_a, rd_addr_b;
  logic [W-1:0]   rd_data_a, rd_data_b;
  always_ff @(posedge clk) begin
    rd_data_a <= ram[rd_addr_a];
    rd_data_b <= ram[rd_addr_b];
  end

  // ACF accumulators
  logic [ACCW-1:0] autocorr_accum, best_score;  // best_score holds **normalized** score
  logic [LW-1:0]   best_lag;

  // pairs helper
  function automatic [AW:0] pairs_for(input [AW:0] vcount, input [LW-1:0] lag);
    if (vcount > {{(AW+1-LW){1'b0}}, lag})
      pairs_for = vcount - {{(AW+1-LW){1'b0}}, lag};
    else
      pairs_for = '0;
  endfunction

  // -------- per-lag normalization (removes small-lag bias) --------
  logic [AW:0]       j_limit_nz;
  logic [ACCW-1:0]   norm_score;
  always_comb begin
    j_limit_nz = (j_limit == 0) ? 1 : j_limit;
    norm_score = (autocorr_accum + (j_limit_nz>>1)) / j_limit_nz;  // rounded
  end

  // prefer longer lags on near-ties (±3%)
  logic better, close_and_longer;
  always_comb begin
    better           = (norm_score > (best_score + (best_score>>5))); // ~3.125%
    close_and_longer = ((norm_score + (norm_score>>5)) >= best_score) &&
                       ((best_score + (best_score>>5)) >= norm_score) &&
                       (lag_index > best_lag);
  end

  // -------- fused 64-bit BPM math --------
  localparam logic [63:0] SR64  = SAMPLE_RATE;
  localparam logic [63:0] FS64  = FRAME_SIZE;
  localparam logic [63:0] STR64 = STRIDE;

  // refinement state
  logic [$clog2(M_FRAC_STEPS)-1:0] alpha_idx;
  logic [IW-1:0]  a_corr_hold, b0_corr_hold;
  logic [ACCW-1:0] refine_accum, refine_best_score;
  logic [LW+REFINE_FRAC_BITS:0] refine_best_lagfp;

  logic [63:0] n64, d64, q64;
  logic [REFINE_FRAC_BITS:0] w0, w1;
  logic [IW+REFINE_FRAC_BITS:0] t0, t1;
  logic [IW+REFINE_FRAC_BITS+1:0] tsum;
  logic [IW-1:0] b_interp;

  // --------- Post-filter state (median-of-5 / lock / smoothing) ----------
  logic [15:0] bpm_raw16;
  logic [23:0] bpm_q8p8;               // Q8.8 accumulator
  logic [15:0] raw_hist0, raw_hist1, raw_hist2, raw_hist3, raw_hist4;

  logic signed [24:0] delta_q8p8, step_q8p8;
  logic [23:0]        target_q8p8;
  logic [15:0]        prev_bpm_int, lock_win, snapped_bpm;
  logic [15:0]        twice_prev, half_prev;
  logic [15:0]        diff2x, diffHalf;

  logic [15:0] bpm_med;  // median-of-5 result
  logic signed [24:0] slew_lim_q;

  // ---- median-of-5 (rank-based; robust with ties) ----
  function automatic [15:0] median5(
      input [15:0] a, input [15:0] b, input [15:0] c,
      input [15:0] d, input [15:0] e
  );
    logic [2:0] ra, rb, rc, rd, re;
    logic [2:0] da, db, dc, dd, de;
    logic [2:0] min_diff;
    logic [15:0] med;
    begin
      ra = (b < a) + (c < a) + (d < a) + (e < a);
      rb = (a < b) + (c < b) + (d < b) + (e < b);
      rc = (a < c) + (b < c) + (d < c) + (e < c);
      rd = (a < d) + (b < d) + (c < d) + (e < d);
      re = (a < e) + (b < e) + (c < e) + (d < e);

      if      (ra == 3'd2) med = a;
      else if (rb == 3'd2) med = b;
      else if (rc == 3'd2) med = c;
      else if (rd == 3'd2) med = d;
      else if (re == 3'd2) med = e;
      else begin
        // fallback: choose rank closest to 2 (stable priority a..e)
        da = (ra > 3'd2) ? (ra - 3'd2) : (3'd2 - ra);
        db = (rb > 3'd2) ? (rb - 3'd2) : (3'd2 - rb);
        dc = (rc > 3'd2) ? (rc - 3'd2) : (3'd2 - rc);
        dd = (rd > 3'd2) ? (rd - 3'd2) : (3'd2 - rd);
        de = (re > 3'd2) ? (re - 3'd2) : (3'd2 - re);
        min_diff = da;
        med      = a;
        if (db < min_diff) begin min_diff = db; med = b; end
        if (dc < min_diff) begin min_diff = dc; med = c; end
        if (dd < min_diff) begin min_diff = dd; med = d; end
        if (de < min_diff) begin min_diff = de; med = e; end
      end
      median5 = med;
    end
  endfunction

  // FSM
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      state          <= IDLE;
      lag_index      <= (LOWER_LAG_FR>0)?LOWER_LAG_FR[LW-1:0]:'0;
      j_index        <= '0;
      j_limit        <= '0;
      last_iter      <= 1'b0;
      last_iter_s    <= 1'b0;
      rd_addr_a      <= '0;
      rd_addr_b      <= '0;
      autocorr_accum <= '0;
      best_score     <= '0;
      best_lag       <= (LOWER_LAG_FR>0)?LOWER_LAG_FR[LW-1:0]:'0;
      bpm_valid      <= 1'b0;
      BPM_estimate   <= 16'd0;

      alpha_idx          <= '0;
      j_index_ref        <= '0;
      j_limit_ref        <= '0;
      a_corr_hold        <= '0;
      b0_corr_hold       <= '0;
      refine_accum       <= '0;
      refine_best_score  <= '0;
      refine_best_lagfp  <= '0;

      n64 <= '0; d64 <= '0; q64 <= '0;
      w0  <= '0; w1  <= '0;
      t0  <= '0; t1  <= '0; tsum <= '0; b_interp <= '0;

      // post-filter state
      bpm_q8p8   <= 24'd0;
      raw_hist0  <= 16'd0;
      raw_hist1  <= 16'd0;
      raw_hist2  <= 16'd0;
      raw_hist3  <= 16'd0;
      raw_hist4  <= 16'd0;

    end else begin
      bpm_valid <= 1'b0;

      unique case (state)
        // ===== integer sweep =====
        IDLE: begin
          if (start_req) begin
            lag_index      <= (LOWER_LAG_FR>0)?LOWER_LAG_FR[LW-1:0]:'0;
            j_index        <= '0;
            j_limit        <= pairs_for(valid_count, (LOWER_LAG_FR>0)?LOWER_LAG_FR[LW-1:0]:'0);
            autocorr_accum <= '0;
            best_score     <= '0;
            best_lag       <= (LOWER_LAG_FR>0)?LOWER_LAG_FR[LW-1:0]:'0;
            state          <= ACC_ADDR;
          end
        end

        ACC_ADDR: begin
          if (j_index < j_limit[AW-1:0]) begin
            rd_addr_a <= age_to_addr({1'b0, j_index});
            rd_addr_b <= age_to_addr({1'b0, j_index} + {{(AW+1-LW){1'b0}}, lag_index});
            last_iter <= (j_index == (j_limit[AW-1:0] - 1'b1));
            state     <= ACC_MAC;
          end else begin
            last_iter <= 1'b1;
            state     <= LAG_ADV;
          end
        end

        ACC_MAC: begin
          last_iter_s    <= last_iter;
          autocorr_accum <= autocorr_accum
                          + {{(ACCW-2*IW){1'b0}}, (take_corr(rd_data_a) * take_corr(rd_data_b))};

          if (last_iter_s) state <= LAG_ADV;
          else begin
            j_index <= j_index + 1'b1;
            state   <= ACC_ADDR;
          end
        end

        LAG_ADV: begin
          if (better || close_and_longer) begin
            best_score <= norm_score;
            best_lag   <= lag_index;
          end

          if (lag_index < UPPER_LAG_FR[LW-1:0]) begin
            lag_index      <= lag_index + 1'b1;
            j_index        <= '0;
            j_limit        <= pairs_for(valid_count, lag_index + 1'b1);
            autocorr_accum <= '0;
            state          <= ACC_ADDR;
          end else begin
            state          <= REF_INIT; // refine fractional around best_lag
          end
        end

        // ===== fractional refinement =====
        REF_INIT: begin
          alpha_idx         <= '0;
          j_index_ref       <= '0;
          j_limit_ref       <= pairs_for(valid_count, best_lag + 1'b1);
          refine_accum      <= '0;
          refine_best_score <= best_score;
          refine_best_lagfp <= {best_lag, {REFINE_FRAC_BITS{1'b0}}};
          state             <= REF_ADDR0;
        end

        REF_ADDR0: begin
          if (j_index_ref < j_limit_ref[AW-1:0]) begin
            rd_addr_a <= age_to_addr({1'b0, j_index_ref});
            rd_addr_b <= age_to_addr({1'b0, j_index_ref} + {{(AW+1-LW){1'b0}}, best_lag});
            last_iter <= (j_index_ref == (j_limit_ref[AW-1:0] - 1'b1));
            state     <= REF_ADDR1;
          end else begin
            if (refine_accum > refine_best_score) begin
              refine_best_score <= refine_accum;
              refine_best_lagfp <= ({best_lag, {REFINE_FRAC_BITS{1'b0}}}) + alpha_idx;
            end
            if (alpha_idx == (M_FRAC_STEPS-1)) begin
              // ----- fused single rounded divide for raw BPM -----
              n64 = (64'd60 * SR64) << REFINE_FRAC_BITS;
              d64 = FS64 * STR64 * {{(64-(LW+REFINE_FRAC_BITS+1)){1'b0}}, refine_best_lagfp};
              if (d64 != 64'd0) begin
                q64 = (n64 + (d64>>1)) / d64;
                bpm_raw16 = q64[15:0];
              end else bpm_raw16 = 16'd0;

              // clamp
              if (bpm_raw16 < MIN_BPM) bpm_raw16 = MIN_BPM;
              if (bpm_raw16 > MAX_BPM) bpm_raw16 = MAX_BPM;

              // ===== median-of-5 =====
              raw_hist4 <= raw_hist3;
              raw_hist3 <= raw_hist2;
              raw_hist2 <= raw_hist1;
              raw_hist1 <= raw_hist0;
              raw_hist0 <= bpm_raw16;
              bpm_med   <= median5(bpm_raw16, raw_hist1, raw_hist2, raw_hist3, raw_hist4);

              // ===== tempo lock & harmonic snap (½× / 2×) =====
              prev_bpm_int = (bpm_q8p8 != 24'd0) ? ((bpm_q8p8 + 8'd128) >> 8) : bpm_med;
              lock_win     = (prev_bpm_int >> LOCK_PCT_SHIFT);
              if (lock_win == 16'd0) lock_win = 16'd1;

              twice_prev = prev_bpm_int << 1;
              half_prev  = prev_bpm_int >> 1;

              snapped_bpm = bpm_med;
              if ((twice_prev >= MIN_BPM) && (twice_prev <= MAX_BPM)) begin
                diff2x = (twice_prev > bpm_med) ? (twice_prev - bpm_med) : (bpm_med - twice_prev);
                if (diff2x <= lock_win) snapped_bpm = twice_prev;
              end
              if ((half_prev >= MIN_BPM) && (half_prev <= MAX_BPM)) begin
                diffHalf = (half_prev > bpm_med) ? (half_prev - bpm_med) : (bpm_med - half_prev);
                if (diffHalf <= lock_win) snapped_bpm = half_prev;
              end

              // ===== EMA smoothing with slew limit (Q8.8) =====
              target_q8p8 = {snapped_bpm, 8'd0};
              if (bpm_q8p8 == 24'd0) begin
                bpm_q8p8 <= target_q8p8;
              end else begin
                delta_q8p8 = $signed({1'b0,target_q8p8}) - $signed({1'b0,bpm_q8p8});
                step_q8p8  <= (delta_q8p8 >>> SMOOTH_SHIFT);

                slew_lim_q = $signed({1'b0, SLEW_MAX_BPM, 8'd0});
                if (step_q8p8 >  slew_lim_q) step_q8p8 <=  slew_lim_q;
                if (step_q8p8 < -slew_lim_q) step_q8p8 <= -slew_lim_q;

                bpm_q8p8 <= $unsigned($signed({1'b0,bpm_q8p8}) + step_q8p8);
              end

              BPM_estimate <= (bpm_q8p8 + 8'd128) >> 8;
              bpm_valid    <= 1'b1;
              state        <= IDLE;

            end else begin
              alpha_idx    <= alpha_idx + 1'b1;
              j_index_ref  <= '0;
              refine_accum <= '0;
              state        <= REF_ADDR0;
            end
          end
        end

        REF_ADDR1: begin
          a_corr_hold  <= take_corr(rd_data_a);
          b0_corr_hold <= take_corr(rd_data_b);
          rd_addr_b    <= age_to_addr({1'b0, j_index_ref} + {{(AW+1-LW){1'b0}}, best_lag} + 1'b1);
          state        <= REF_MAC;
        end

        REF_MAC: begin
          w0   <= M_FRAC_STEPS - alpha_idx;
          w1   <= alpha_idx;
          t0   <= b0_corr_hold * w0;
          t1   <= take_corr(rd_data_b) * w1;
          tsum <= t0 + t1;
          b_interp <= (tsum + (M_FRAC_STEPS>>1)) >> REFINE_FRAC_BITS;

          refine_accum <= refine_accum + {{(ACCW-2*IW){1'b0}}, (a_corr_hold * b_interp)};
          j_index_ref  <= j_index_ref + 1'b1;
          state        <= REF_ADDR0;
        end
      endcase
    end
  end
endmodule
