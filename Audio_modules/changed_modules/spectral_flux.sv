module spectral_flux #(
    parameter N = 8,
    parameter W = 16,
    parameter MAX_FLUX_LENGTH = 32,
    parameter PREV_FRAMES_SPEC_FLUX = 4
)(
    input logic clk,
    input logic reset,
    input logic mag_valid,
    input logic [W-1:0] mag_sq,

    output logic [MAX_FLUX_LENGTH-1:0] flux_value,
    output logic flux_valid,

    output logic [MAX_FLUX_LENGTH-1:0] flux_low,
    output logic [MAX_FLUX_LENGTH-1:0] flux_mid,
    output logic [MAX_FLUX_LENGTH-1:0] flux_high,
    output logic beat_valid,
    output logic frame_done,
    output logic [MAX_FLUX_LENGTH-1:0] flux_accum
);

    logic [3:0] counter;
    logic [W-1:0] prev_mag [0:N-1];
    logic [MAX_FLUX_LENGTH-1:0] temp_flux_accum;
    logic [MAX_FLUX_LENGTH-1:0] temp_low, temp_mid, temp_high;
    logic [MAX_FLUX_LENGTH-1:0] flux_history [0:PREV_FRAMES_SPEC_FLUX-1];
    logic [$clog2(PREV_FRAMES_SPEC_FLUX)-1:0] flux_index;
    logic [MAX_FLUX_LENGTH-1:0] flux_sum, flux_mean, threshold;

    // Internal signal to latch mag_sq each valid
    logic [W-1:0] curr_mag;
    logic [W-1:0] prev_val;
    logic signed [W-1:0] diff;
    logic [W-1:0] pos_diff;

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            temp_flux_accum <= 0;
            temp_low <= 0;
            temp_mid <= 0;
            temp_high <= 0;
            flux_valid <= 0;
            beat_valid <= 0;
            frame_done <= 0;
            flux_value <= 0;
            flux_low <= 0;
            flux_mid <= 0;
            flux_high <= 0;
            flux_accum <= 0;
            flux_sum <= 0;
            flux_index <= 0;
            threshold <= 0;
            flux_mean <= 0;

            for (int i = 0; i < N; i++)
                prev_mag[i] <= 0;
            for (int j = 0; j < PREV_FRAMES_SPEC_FLUX; j++)
                flux_history[j] <= 0;
        end
        else begin
            frame_done <= 0;
            flux_valid <= 0;
            beat_valid <= 0;

            if (mag_valid) begin
                curr_mag <= mag_sq;
                prev_val <= prev_mag[counter];

                diff = curr_mag - prev_val;
                pos_diff = (diff[W-1] == 0) ? diff : 0;

                temp_flux_accum <= temp_flux_accum + pos_diff;
                prev_mag[counter] <= curr_mag;

                // Band mapping
                if (curr_mag < 512)
                    temp_low <= temp_low + pos_diff;
                else if (curr_mag < 1024)
                    temp_mid <= temp_mid + pos_diff;
                else
                    temp_high <= temp_high + pos_diff;

                if (counter == N - 1) begin
                    // Frame done
                    frame_done <= 1;
                    flux_accum <= temp_flux_accum;
                    flux_value <= temp_flux_accum;
                    flux_low <= temp_low;
                    flux_mid <= temp_mid;
                    flux_high <= temp_high;
                    flux_valid <= 1;

                    // History buffer for beat detection
                    flux_sum <= flux_sum - flux_history[flux_index] + temp_flux_accum;
                    flux_history[flux_index] <= temp_flux_accum;
                    flux_index <= (flux_index == PREV_FRAMES_SPEC_FLUX - 1) ? 0 : flux_index + 1;

                    flux_mean <= flux_sum / PREV_FRAMES_SPEC_FLUX;
                    threshold <= (flux_sum / PREV_FRAMES_SPEC_FLUX) << 1; // 2x mean
                    beat_valid <= (temp_flux_accum > threshold) ? 1 : 0;

                    // Reset accumulators
                    temp_flux_accum <= 0;
                    temp_low <= 0;
                    temp_mid <= 0;
                    temp_high <= 0;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end
endmodule
