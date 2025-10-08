// snr_calculator.sv
// Streaming SNR estimator with EMA-based moving averages (quiet-calibrated noise).
// Adds baseline-subtracted SNR (snr_db_delta) for display headroom.
//
// New params:
//   DISP_SCALE_SHIFT : left-shift applied to (snr_db - baseline) before clamp.
//                      Use 0 to keep raw delta in dB, 1 to multiply by 2, etc.
// New outputs:
//   snr_db_delta     : 0..255, baseline-subtracted (and scaled) SNR for display.

module snr_calculator #(
    // ------- SNR params -------
    parameter int DATA_WIDTH       = 16,
    parameter int SNR_WIDTH        = 8,
    parameter int SIG_SHIFT        = 6,    // alpha_s = 1/64  (fast)
    parameter int NOISE_SHIFT      = 12,   // alpha_l = 1/4096 (slow)

    // ------- Display headroom helper -------
    parameter int DISP_SCALE_SHIFT = 0,    // scale snr_delta before clamp (0 = ×1)

    // ------- BPM passthrough params -------
    parameter int  BPM_WIDTH       = 16,
    parameter int  BPM_MAX         = 200   // threshold for halving
)(
    input  logic                          clk,
    input  logic                          reset,          // active-high sync reset
    input  logic                          quiet_period,   // assert during quiet calibration

    // -------- Audio stream (signed) --------
    input  logic signed [DATA_WIDTH-1:0]  audio_input,
    input  logic                          audio_input_valid,
    output logic                          audio_input_ready,

    // -------- SNR results --------
    output logic [SNR_WIDTH-1:0]          snr_db,         // absolute SNR (≈ dB)
    output logic [SNR_WIDTH-1:0]          snr_db_delta,   // NEW: baseline-subtracted SNR
    output logic [DATA_WIDTH-1:0]         signal_rms,
    output logic [DATA_WIDTH-1:0]         noise_rms,
    output logic                          output_valid,
    input  logic                          output_ready,

    // -------- BPM passthrough (registered) --------
    input  logic       [BPM_WIDTH-1:0]    bpm_in,        // EXPECT UNSIGNED
    input  logic                          bpm_valid_in,
    output logic       [BPM_WIDTH-1:0]    bpm_out,
    output logic                          bpm_valid_out
);

    // ------------ Handshake ------------
    assign audio_input_ready = output_ready;

    // ------------ |x[n]| ------------
    logic [DATA_WIDTH-1:0] abs_samp;
    always_comb begin
        abs_samp = audio_input[DATA_WIDTH-1] ? (~audio_input + 1'b1) : audio_input;
    end

    // ------------ EMA accumulators ------------
    localparam int ACC_WIDTH = DATA_WIDTH + 16;
    localparam logic signed [ACC_WIDTH-1:0] EPS = 'd1;

    logic signed [ACC_WIDTH-1:0] sig_accum, noise_accum;
    logic signed [ACC_WIDTH-1:0] samp_ext;

    always_comb begin
        samp_ext = $signed({{(ACC_WIDTH-DATA_WIDTH){1'b0}}, abs_samp});
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            sig_accum    <= EPS;
            noise_accum  <= EPS;
            output_valid <= 1'b0;
        end else begin
            output_valid <= 1'b0;
            if (audio_input_valid && audio_input_ready) begin
                // Signal EMA: fast, always updates
                sig_accum   <= sig_accum   + ((samp_ext - sig_accum)   >>> SIG_SHIFT);

                // Noise EMA: only update during quiet calibration window
                if (quiet_period) begin
                    noise_accum <= noise_accum + ((samp_ext - noise_accum) >>> NOISE_SHIFT);
                end
                // else: hold last noise level

                output_valid <= 1'b1;
            end
        end
    end

    // Narrow for visibility (truncate)
    assign signal_rms = sig_accum  [DATA_WIDTH-1:0];
    assign noise_rms  = noise_accum[DATA_WIDTH-1:0];

    // ------------ log2 approximation (Q8.8) ------------
    function automatic [15:0] log2_q8 (input logic [31:0] v);
        int i; logic [7:0] msb; int unsigned sh; logic [31:0] norm; logic [7:0] frac;
        begin
            if (v == 0) log2_q8 = 16'd0;
            else begin
                msb = 8'd0;
                for (i = 31; i >= 0; i--) if (v[i]) begin msb = i[7:0]; break; end
                sh   = 31 - msb;
                norm = v << sh;      // normalize to [1,2)
                frac = norm[30:23];  // next 8 bits
                log2_q8 = {msb, frac};
            end
        end
    endfunction

    // SNR_dB ≈ 6.02 * (log2(sig) - log2(noise))
    logic [15:0] l2s, l2n, l2d, db_q8;
    logic [31:0] mult_tmp;
    logic signed [31:0] sig_clip, noise_clip;

    always_comb begin
        sig_clip   = (sig_accum   > 0) ? sig_accum  [31:0] : 32'd1;
        noise_clip = (noise_accum > 0) ? noise_accum[31:0] : 32'd1;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            l2s <= '0; l2n <= '0; l2d <= '0; db_q8 <= '0; mult_tmp <= '0;
        end else if (audio_input_valid && audio_input_ready) begin
            l2s      <= log2_q8(sig_clip);
            l2n      <= log2_q8(noise_clip);
            l2d      <= l2s - l2n;
            mult_tmp <= l2d * 32'd1546;   // ~6.02 * 256
            db_q8    <= mult_tmp[23:8];   // Q8.8
        end
    end

    // Absolute SNR in integer dB (0..255)
    always_comb begin
        if ($signed(db_q8[15:8]) < 0) snr_db = '0;
        else                           snr_db = db_q8[15:8];
    end

    // ------------ NEW: baseline-subtracted SNR for display headroom ------------
    // While quiet_period=1 (e.g., hold KEY0), update baseline to current absolute SNR.
    // When quiet_period=0, hold & use it as the offset.
    logic [SNR_WIDTH-1:0] snr_base;
    always_ff @(posedge clk) begin
        if (reset) begin
            snr_base <= '0;
        end else if (output_valid && quiet_period) begin
            snr_base <= snr_db;  // track baseline during quiet calibration
        end
    end

    // snr_delta = max(0, (snr_db - snr_base)) << DISP_SCALE_SHIFT, with clamp
    logic [SNR_WIDTH:0] delta_raw;        // one extra bit for subtract
    logic [SNR_WIDTH+4:0] delta_scaled;   // enough headroom for small shifts
    always_comb begin
        delta_raw    = (snr_db >= snr_base) ? (snr_db - snr_base) : '0;
        delta_scaled = delta_raw << DISP_SCALE_SHIFT;
        // clamp to 0..255 (or SNR_WIDTH-specified max)
        if (delta_scaled > {{(SNR_WIDTH+5-SNR_WIDTH){1'b0}}, {SNR_WIDTH{1'b1}}})
            snr_db_delta = {SNR_WIDTH{1'b1}};
        else
            snr_db_delta = delta_scaled[SNR_WIDTH-1:0];
    end

    // ------------ BPM passthrough (REGISTERED; halve once if > BPM_MAX) ------------
    localparam logic [BPM_WIDTH-1:0] BPM_MAX_U = logic'(BPM_MAX);

    logic [BPM_WIDTH-1:0] bpm_in_u;
    always_comb bpm_in_u = bpm_in; // treat input as unsigned

    logic [BPM_WIDTH-1:0] bpm_next;
    always_comb begin
        bpm_next = (bpm_in_u > BPM_MAX_U) ? (bpm_in_u >> 1) : bpm_in_u;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            bpm_out       <= '0;
            bpm_valid_out <= 1'b0;
        end else begin
            bpm_out       <= bpm_next;
            bpm_valid_out <= bpm_valid_in;
        end
    end

endmodule
