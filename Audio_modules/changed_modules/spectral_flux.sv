module spectral_flux #(
    parameter N = 8,
    parameter W = 16,
    parameter MAX_FLUX_LENGTH = 32,
    parameter PREV_FRAMES_SPEC_FLUX = 4
)(
    input  logic clk,
    input  logic reset,
    input  logic mag_valid,
    input  logic [W-1:0] mag_sq,

    output logic [MAX_FLUX_LENGTH-1:0] flux_value,
    output logic flux_valid,
    output logic [MAX_FLUX_LENGTH-1:0] flux_low,
    output logic [MAX_FLUX_LENGTH-1:0] flux_mid,
    output logic [MAX_FLUX_LENGTH-1:0] flux_high,
    output logic beat_valid,
    output logic frame_done,
    output logic [MAX_FLUX_LENGTH-1:0] flux_accum
);

    // Counter and memory
    logic [3:0] counter;
    logic [W-1:0] prev_mag [0:N-1];

    // Difference computation
    logic signed [W-1:0] diff;
    logic [W-1:0] pos_diff;

    // Accumulators
    logic [MAX_FLUX_LENGTH-1:0] temp_flux_accum;
    logic [MAX_FLUX_LENGTH-1:0] temp_low, temp_mid, temp_high;

    // Beat detection
    logic [MAX_FLUX_LENGTH-1:0] flux_history [0:PREV_FRAMES_SPEC_FLUX-1];
    logic [$clog2(PREV_FRAMES_SPEC_FLUX)-1:0] flux_index;
    logic [MAX_FLUX_LENGTH-1:0] flux_sum, flux_mean, threshold;

    integer i;

    always_ff @(posedge clk) begin
        if (reset) begin
            counter       <= 0;
            flux_value    <= 0;
            flux_valid    <= 0;
            flux_low      <= 0;
            flux_mid      <= 0;
            flux_high     <= 0;
            beat_valid    <= 0;
            frame_done    <= 0;
            flux_accum    <= 0;

            temp_flux_accum <= 0;
            temp_low        <= 0;
            temp_mid        <= 0;
            temp_high       <= 0;

            flux_sum     <= 0;
            flux_mean    <= 0;
            threshold    <= 0;
            flux_index   <= 0;

            // Initialize all memory arrays
            for (i = 0; i < N; i = i + 1)
                prev_mag[i] <= 0;
            for (i = 0; i < PREV_FRAMES_SPEC_FLUX; i = i + 1)
                flux_history[i] <= 0;
        end
        else begin
            frame_done <= 0;
            flux_valid <= 0;
            beat_valid <= 0;

            if (mag_valid) begin
                // Calculate positive difference
                diff = $signed(mag_sq) - $signed(prev_mag[counter]);
                if (diff >= 0)
                    pos_diff = diff;
                else
                    pos_diff = 0;

                // Update accumulators
                temp_flux_accum <= temp_flux_accum + pos_diff;
                prev_mag[counter] <= mag_sq;

                // Band mapping
                if (mag_sq < 512)
                    temp_low <= temp_low + pos_diff;
                else if (mag_sq < 1024)
                    temp_mid <= temp_mid + pos_diff;
                else
                    temp_high <= temp_high + pos_diff;

                // Check for end of frame
                if (counter == N - 1) begin
                    flux_accum <= temp_flux_accum;
                    flux_value <= temp_flux_accum;
                    flux_low   <= temp_low;
                    flux_mid   <= temp_mid;
                    flux_high  <= temp_high;

                    frame_done <= 1;
                    flux_valid <= 1;

                    // Beat detection logic
                    flux_sum <= flux_sum - flux_history[flux_index] + temp_flux_accum;
                    flux_history[flux_index] <= temp_flux_accum;
                    flux_index <= (flux_index == PREV_FRAMES_SPEC_FLUX - 1) ? 0 : flux_index + 1;

                    flux_mean <= flux_sum / PREV_FRAMES_SPEC_FLUX;
                    threshold <= (flux_sum / PREV_FRAMES_SPEC_FLUX) << 1;

                    beat_valid <= (temp_flux_accum > threshold);

                    // Reset accumulators
                    temp_flux_accum <= 0;
                    temp_low  <= 0;
                    temp_mid  <= 0;
                    temp_high <= 0;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

endmodule
