// bpm_estimator_windowed_safe.sv
// Window-based detector with hysteresis, warm-up, and interval gating.
// Ports/params unchanged from your version.

module bpm_estimator #(
    parameter W = 16,
    parameter SAMPLE_FREQ    = 12000, // Hz (decimated rate)
    parameter WINDOW_MS      = 30,    // ms per decision window
    parameter THRESHOLD_SCALE= 2,     // legacy (unused directly; we use HI/LO below)
    parameter REFRAC_TIMER   = 150    // ms lockout after a beat
)(
    input  logic                clk,
    input  logic                reset,
    input  logic signed [W-1:0] signal_rms,
    input  logic                sample_tick,

    output logic                beat_pulse,
    output logic [W-1:0]        beat_strength,
    output logic [15:0]         BPM_estimate
);

    // ---------------- derived constants ----------------
    localparam int unsigned WINDOW_SIZE   = (SAMPLE_FREQ * WINDOW_MS)   / 1000;  // samples/window
    localparam int unsigned REFRAC_CYCLES = (SAMPLE_FREQ * REFRAC_TIMER)/ 1000;  // samples
    // BPM validity range (edit to taste)
    localparam int unsigned MIN_BPM = 40;
    localparam int unsigned MAX_BPM = 240;
    localparam int unsigned MIN_INT = (60 * SAMPLE_FREQ) / MAX_BPM;  // shortest plausible interval (samples)
    localparam int unsigned MAX_INT = (60 * SAMPLE_FREQ) / MIN_BPM;  // longest plausible interval  (samples)
    // Hysteresis in Q3 (×8): HI=17/16 ≈ +6.25%, LO=15/16 ≈ −6.25%
    localparam int SCALE_Q  = 3;
    localparam int HI_SCALE = 17;
    localparam int LO_SCALE = 15;
    // Warm-up windows before allowing triggers
    localparam int unsigned WARMUP_WINDOWS = 4;

    // ---------------- regs/wires ----------------
    logic sample_tick_d;
    wire  sample_tick_pulse;

    logic [31:0] window_counter;
    logic [63:0] energy_accum;   // sum(|x|^2) over window
    logic [63:0] avg_energy;     // smoothed window energy

    logic [31:0] refractory_counter;
    logic        refractory_active;

    logic [31:0] interval_counter;         // samples since last accepted beat

    // hysteresis/arming across windows
    logic        armed;                     // allow trigger when 1
    logic        above_hi, above_lo;

    // warm-up
    logic [7:0]  warmup_cnt;
    logic        warmed_up;

    // temps (module-scope for Quartus)
    logic [2*W-1:0] e2;
    logic [63:0]    e64;
    logic [63:0]    slow_q_hi, slow_q_lo;

    // sample-rate pulse
    always_ff @(posedge clk or posedge reset) begin
        if (reset) sample_tick_d <= 1'b0;
        else       sample_tick_d <= sample_tick;
    end
    assign sample_tick_pulse = sample_tick & ~sample_tick_d;

    // main
    always_ff @(posedge clk) begin
        if (reset) begin
            beat_pulse         <= 1'b0;
            beat_strength      <= '0;
            BPM_estimate       <= '0;

            window_counter     <= '0;
            energy_accum       <= '0;
            avg_energy         <= 64'd1;     // avoid 0

            refractory_counter <= '0;
            refractory_active  <= 1'b0;

            interval_counter   <= '0;

            armed              <= 1'b0;      // arm after warm-up
            above_hi           <= 1'b0;
            above_lo           <= 1'b0;

            warmup_cnt         <= '0;
            warmed_up          <= 1'b0;
        end else begin
            beat_pulse <= 1'b0; // default

            if (sample_tick_pulse) begin
                // accumulate energy (|x|^2) safely widened
                e2  = $unsigned(signal_rms) * $unsigned(signal_rms);
                e64 = {{(64-2*W){1'b0}}, e2};

                energy_accum   <= energy_accum + e64;
                window_counter <= window_counter + 1;
                interval_counter <= interval_counter + 1;

                // refractory at sample cadence
                if (refractory_active) begin
                    if (refractory_counter != 0)
                        refractory_counter <= refractory_counter - 1;
                    else
                        refractory_active  <= 1'b0;
                end

                // end of window: decide once per window
                if (window_counter == WINDOW_SIZE-1) begin
                    // update avg: simple IIR (1/16 new, 15/16 old)
                    avg_energy <= (avg_energy - (avg_energy >> 4)) + (energy_accum >> 4);

                    // warm-up handling
                    if (!warmed_up) begin
                        if (warmup_cnt == WARMUP_WINDOWS-1) begin
                            warmed_up <= 1'b1;
                            armed     <= 1'b1;  // arm after warm-up
                        end else begin
                            warmup_cnt <= warmup_cnt + 1;
                        end
                    end

                    // hysteresis comparisons on window sums
                    slow_q_hi <= avg_energy * HI_SCALE;         // slow * HI (Q3)
                    slow_q_lo <= avg_energy * LO_SCALE;         // slow * LO (Q3)
                    // compare energy_accum<<Q to slow*scale
                    above_hi  <= ((energy_accum << SCALE_Q) > slow_q_hi);
                    above_lo  <= ((energy_accum << SCALE_Q) > slow_q_lo);

                    // re-arm only when below LO
                    if (!above_lo) armed <= 1'b1;

                    // trigger when: warmed up, armed, not in refractory, and just above HI
                    if (warmed_up && armed && !refractory_active && above_hi) begin
                        armed         <= 1'b0;                  // disarm until below LO
                        beat_pulse    <= 1'b1;
                        beat_strength <= energy_accum[W-1:0];

                        // accept only plausible intervals; ignore tiny/random ones
                        if ((interval_counter >= MIN_INT) && (interval_counter <= MAX_INT)) begin
                            // Rounded BPM
                            logic [31:0] num, den, bpm_rnd;
                            num     = (60 * SAMPLE_FREQ);
                            den     = interval_counter;
                            bpm_rnd = (num + (den >> 1)) / den;

                            // clamp
                            if (bpm_rnd < MIN_BPM)       BPM_estimate <= MIN_BPM[15:0];
                            else if (bpm_rnd > MAX_BPM)  BPM_estimate <= MAX_BPM[15:0];
                            else                          BPM_estimate <= bpm_rnd[15:0];
                        end
                        // reset timers
                        interval_counter   <= 0;
                        refractory_counter <= REFRAC_CYCLES;
                        refractory_active  <= 1'b1;
                    end

                    // reset window integrator/counter
                    energy_accum   <= '0;
                    window_counter <= '0;
                end
            end
        end
    end
endmodule
