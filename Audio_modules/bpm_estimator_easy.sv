// bpm_estimator_fixed.sv
module bpm_estimator #(
    parameter W = 16,                    // sample width of signal_rms (signed or unsigned)
    parameter integer SAMPLE_FREQ = 12000,
    parameter integer WINDOW_MS = 10,
    parameter integer THRESHOLD_SCALE = 2, // multiplicative threshold on energy ratio
    parameter integer REFRAC_TIMER_MS = 200, // ms
    parameter integer MAX_BPM_ACCEPT = 300,  // reject intervals shorter than this BPM
    parameter integer SMOOTH_ALPHA = 8       // smoothing factor for BPM (>=1)
)(
    input  logic                     clk,
    input  logic                     reset,
    input  logic signed [W-1:0]     signal_rms,    // envelope / RMS (signed OK)
    input  logic                     sample_tick,   // may be multi-cycle valid -> we edge detect

    output logic                     beat_pulse,
    output logic [W-1:0]             beat_strength,
    output logic [15:0]              BPM_estimate
);

    // ---------- derived params ----------
    localparam integer WINDOW_SIZE = (SAMPLE_FREQ * WINDOW_MS) / 1000;
    localparam integer REFRAC_CYCLES = (SAMPLE_FREQ * REFRAC_TIMER_MS) / 1000;
    // minimum allowed samples between beats (prevents ridiculously high BPM)
    localparam integer MIN_INTERVAL_SAMPLES = (SAMPLE_FREQ * 60) / MAX_BPM_ACCEPT;

    // ---------- sample_tick edge-detect (sync two-stage) ----------
    logic tick_sync_0, tick_sync_1;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tick_sync_0 <= 1'b0;
            tick_sync_1 <= 1'b0;
        end else begin
            tick_sync_0 <= sample_tick;
            tick_sync_1 <= tick_sync_0;
        end
    end
    wire sample_tick_pulse = tick_sync_1 & ~tick_sync_0; // one-cycle pulse in clk domain

    // ---------- internal state ----------
    logic [31:0] window_counter;
    logic [63:0] energy_accum;
    logic [63:0] avg_energy;

    logic [31:0] refractory_counter;
    logic        refractory_active;

    logic [31:0] interval_counter;
    logic [31:0] last_interval_counter_val;

    // energy ratio Q16 and previous ratio for rising-edge detection
    logic [31:0] energy_ratio_q16;
    logic [31:0] prev_energy_ratio_q16;

    // smoothing for BPM in Q16
    logic [31:0] smoothed_bpm_q16;

    // ---------- initialize ----------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            beat_pulse <= 1'b0;
            beat_strength <= '0;
            BPM_estimate <= 16'd0;

            window_counter <= 32'd0;
            energy_accum <= 64'd0;
            avg_energy <= 64'd1; // avoid divide-by-zero

            refractory_counter <= 0;
            refractory_active <= 1'b0;

            interval_counter <= 0;
            last_interval_counter_val <= 0;

            energy_ratio_q16 <= 32'd0;
            prev_energy_ratio_q16 <= 32'd0;

            smoothed_bpm_q16 <= 32'd0;
        end else begin
            beat_pulse <= 1'b0;

            // store previous ratio for rising-edge detection
            prev_energy_ratio_q16 <= energy_ratio_q16;

            // only update counters+accumulators on a clean sample pulse
            if (sample_tick_pulse) begin
                // increment counters (per sample)
                interval_counter <= interval_counter + 1;
                window_counter <= window_counter + 1;

                // square: handle signed/unsigned safely by casting to signed 32-bit then abs
                logic signed [31:0] s;
                logic [31:0] sq;
                s = $signed(signal_rms);
                // absolute value
                if (s < 0) sq = $unsigned(-s) * $unsigned(-s);
                else       sq = $unsigned(s)  * $unsigned(s);
                energy_accum <= energy_accum + {32'd0, sq}; // 64-bit accumulation

                // when window ends, compute ratio and possibly detect beat
                if (window_counter >= WINDOW_SIZE - 1) begin
                    // compute ratio Q16 = (energy_accum << 16) / avg_energy (guard avg_energy != 0)
                    if (avg_energy == 0) energy_ratio_q16 <= 32'd0;
                    else begin
                        // widen and divide
                        logic [95:0] numer;
                        numer = {energy_accum, 16'd0}; // energy_accum << 16
                        energy_ratio_q16 <= numer / avg_energy;
                    end

                    // rising edge detection and threshold compare
                    // threshold in Q16 = THRESHOLD_SCALE << 16
                    if (!refractory_active &&
                        (energy_ratio_q16 > (THRESHOLD_SCALE << 16)) &&
                        (prev_energy_ratio_q16 <= (THRESHOLD_SCALE << 16)) &&
                        (interval_counter >= MIN_INTERVAL_SAMPLES) ) begin

                        // fire beat
                        beat_pulse <= 1'b1;
                        beat_strength <= energy_accum[W-1:0];

                        // compute BPM in Q16: (60 * SAMPLE_FREQ << 16) / interval_counter
                        if (interval_counter != 0) begin
                            logic [63:0] numer_bpm;
                            logic [31:0] bpm_q16;
                            numer_bpm = (60 * SAMPLE_FREQ);
                            numer_bpm = numer_bpm << 16; // Q16
                            bpm_q16 = numer_bpm / interval_counter;
                            // smoothing
                            if (SMOOTH_ALPHA <= 1) smoothed_bpm_q16 <= bpm_q16;
                            else smoothed_bpm_q16 <= ((smoothed_bpm_q16 * (SMOOTH_ALPHA - 1)) + bpm_q16) / SMOOTH_ALPHA;

                            BPM_estimate <= smoothed_bpm_q16[31:16];
                        end

                        last_interval_counter_val <= interval_counter;
                        interval_counter <= 0;

                        // enter refractory
                        refractory_counter <= REFRAC_CYCLES;
                        refractory_active <= 1'b1;
                    end

                    // update exponential moving average for energy (simple IIR)
                    avg_energy <= (avg_energy * 15 + energy_accum) >> 4;

                    // reset window accumulators
                    energy_accum <= 64'd0;
                    window_counter <= 32'd0;
                end
            end // sample_tick_pulse

            // refractory countdown (sample ticks)
            if (refractory_active) begin
                if (refractory_counter > 0) refractory_counter <= refractory_counter - 1;
                else refractory_active <= 1'b0;
            end
        end
    end

endmodule
