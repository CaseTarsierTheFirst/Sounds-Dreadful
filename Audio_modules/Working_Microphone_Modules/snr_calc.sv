// snr_calculator.sv
// Streaming SNR estimator with EMA-based moving averages per lecture LCCDEs.
// - Short MA (signal): always updates, fast (large alpha = small SHIFT)
// - Long  MA (noise): updates ONLY when quiet_period=1, slow (small alpha)

module snr_calculator #(
    parameter int DATA_WIDTH  = 16,
    parameter int SNR_WIDTH   = 8,
    parameter int SIG_SHIFT   = 6,   // alpha_s = 1/64  (fast)
    parameter int NOISE_SHIFT = 12   // alpha_l = 1/4096 (slow)
)(
    input  logic                  clk,
    input  logic                  reset,          // active-high sync reset
    input  logic                  quiet_period,   // assert during quiet calibration

    // Audio stream
    input  logic [DATA_WIDTH-1:0] audio_input,
    input  logic                  audio_input_valid,
    output logic                  audio_input_ready,

    // Results
    output logic [SNR_WIDTH-1:0]  snr_db,
    output logic [DATA_WIDTH-1:0] signal_rms,
    output logic [DATA_WIDTH-1:0] noise_rms,
    output logic                  output_valid,
    input  logic                  output_ready
);

    // Handshake: accept a sample whenever downstream is ready
    assign audio_input_ready = output_ready;

    // -------- absolute value |x[n]| --------
    logic [DATA_WIDTH-1:0] abs_samp;
    always_comb begin
        abs_samp = audio_input[DATA_WIDTH-1] ? (~audio_input + 1'b1) : audio_input;
    end

    // -------- EMA accumulators (widened) --------
    // Use the LCCDE form: y <= y + ((x - y) >>> SHIFT)
    localparam int ACC_WIDTH = DATA_WIDTH + 16;
    logic signed [ACC_WIDTH-1:0] sig_accum, noise_accum;
    localparam logic [ACC_WIDTH-1:0] EPS = 1;  // tiny floor

    always_ff @(posedge clk) begin
        if (reset) begin
            sig_accum   <= EPS;
            noise_accum <= EPS;
            output_valid <= 1'b0;
        end else begin
            output_valid <= 1'b0;
            if (audio_input_valid && audio_input_ready) begin
                // Short MA: always update (fast)
                sig_accum <= sig_accum + ( ( $signed({{(ACC_WIDTH-DATA_WIDTH){1'b0}},abs_samp}) - sig_accum ) >>> SIG_SHIFT );

                // Long MA: update only when quiet_period = 1 (slow)
                if (quiet_period) begin
                    noise_accum <= noise_accum +
                        ( ( $signed({{(ACC_WIDTH-DATA_WIDTH){1'b0}},abs_samp}) - noise_accum ) >>> NOISE_SHIFT );
                end
                // else: hold noise_accum

                output_valid <= 1'b1;
            end
        end
    end

    // Narrow for visibility (truncate)
    assign signal_rms = sig_accum  [DATA_WIDTH-1:0];
    assign noise_rms  = noise_accum[DATA_WIDTH-1:0];

    // -------- log2 approximation (Q8.8) --------
    function automatic [15:0] log2_q8 (input [31:0] v);
        int i;
        logic [7:0] msb;
        int unsigned sh;
        logic [31:0] norm;
        logic [7:0] frac;
        begin
            if (v == 0) begin
                log2_q8 = 16'd0;
            end else begin
                msb = 8'd0;
                for (i = 31; i >= 0; i = i - 1)
                    if (v[i]) begin msb = i[7:0]; break; end
                sh   = 31 - msb;
                norm = v << sh;          // normalize to [1,2)
                frac = norm[30:23];      // next 8 bits
                log2_q8 = {msb, frac};   // Q8.8
            end
        end
    endfunction

    // -------- SNR_dB ≈ 6.02 * (log2(sig) - log2(noise)) --------
    logic [15:0] l2s, l2n, l2d, db_q8;
    logic [31:0] mult_tmp;

    wire [31:0] sig_clip   = (sig_accum   > 0) ? sig_accum  [31:0] : 32'd1;
    wire [31:0] noise_clip = (noise_accum > 0) ? noise_accum[31:0] : 32'd1;

    always_ff @(posedge clk) begin
        if (reset) begin
            l2s <= '0; l2n <= '0; l2d <= '0; db_q8 <= '0; mult_tmp <= '0;
        end else if (audio_input_valid && audio_input_ready) begin
            l2s      <= log2_q8(sig_clip);
            l2n      <= log2_q8(noise_clip);
            l2d      <= l2s - l2n;
            mult_tmp <= l2d * 32'd1546;     // ~6.02 * 256
            db_q8    <= mult_tmp[23:8];
        end
    end

    always_comb begin
        if ($signed(db_q8[15:8]) < 0) snr_db = '0;
        else                           snr_db = db_q8[15:8];
    end

endmodule
