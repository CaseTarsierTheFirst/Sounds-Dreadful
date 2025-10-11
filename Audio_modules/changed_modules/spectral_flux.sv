module spectral_flux #(
    parameter N = 8,
    parameter W = 64,
    parameter BIN_LENGTH = 10,
    parameter MAX_FLUX_LENGTH = 70,
    parameter PREV_FRAMES_SPEC_FLUX = 32
)(
    input logic clk,
    input logic reset,
    input logic mag_valid,
    input logic [W-1:0] mag_sq,

    output logic [MAX_FLUX_LENGTH - 1:0] flux_value,
    output logic flux_valid,

    output logic [MAX_FLUX_LENGTH - 1:0] flux_low,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_mid,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_high,
    output logic beat_valid,
    output logic frame_done,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_accum
);

    logic [BIN_LENGTH-1:0] counter;
    logic [W-1:0] prev_mag [0:N-1];
    logic signed [W-1:0] diff;
    logic [W-1:0] pos_diff;

    logic [MAX_FLUX_LENGTH-1:0] accum_low, accum_mid, accum_high;
    logic [MAX_FLUX_LENGTH-1:0] flux_history [0:PREV_FRAMES_SPEC_FLUX-1];
    logic [$clog2(PREV_FRAMES_SPEC_FLUX)-1:0] flux_index;
    logic [MAX_FLUX_LENGTH-1:0] flux_sum;
    logic [MAX_FLUX_LENGTH-1:0] flux_mean;
    logic [MAX_FLUX_LENGTH-1:0] threshold;

    logic [4:0] valid_counter;

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            flux_accum <= 0;
            accum_low <= 0;
            accum_mid <= 0;
            accum_high <= 0;
            frame_done <= 0;
            flux_valid <= 0;
            beat_valid <= 0;
            flux_index <= 0;
            flux_sum <= 0;
            flux_mean <= 0;
            threshold <= 0;
            flux_value <= 0;
            flux_low <= 0;
            flux_mid <= 0;
            flux_high <= 0;
            valid_counter <= 0;
        end else begin
            frame_done <= 0; // Default to 0

            if (mag_valid) begin
                prev_mag[counter] <= mag_sq;
                diff = mag_sq - prev_mag[counter];
                pos_diff = (diff[W-1] == 1'b0) ? diff : 0;

                flux_accum <= flux_accum + pos_diff;

                if (mag_sq < 512)
                    accum_low <= accum_low + pos_diff;
                else if (mag_sq < 1024)
                    accum_mid <= accum_mid + pos_diff;
                else
                    accum_high <= accum_high + pos_diff;

                if (counter == N - 1) begin
                    frame_done <= 1;
                    flux_value <= flux_accum;
                    flux_valid <= 1;
                    valid_counter <= 5;

                    flux_low <= accum_low;
                    flux_mid <= accum_mid;
                    flux_high <= accum_high;

                    flux_sum <= flux_sum - flux_history[flux_index] + flux_accum;
                    flux_history[flux_index] <= flux_accum;
                    flux_index <= (flux_index == PREV_FRAMES_SPEC_FLUX - 1) ? 0 : flux_index + 1;

                    flux_mean <= flux_sum / PREV_FRAMES_SPEC_FLUX;
                    threshold <= (flux_sum / PREV_FRAMES_SPEC_FLUX) << 1; // 2x mean
                    beat_valid <= (flux_accum > threshold);

                    // Reset for next frame
                    flux_accum <= 0;
                    accum_low <= 0;
                    accum_mid <= 0;
                    accum_high <= 0;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                // Countdown for valid signal
                if (valid_counter > 0)
                    valid_counter <= valid_counter - 1;
                else
                    flux_valid <= 0;
                    beat_valid <= 0;
            end
        end
    end

endmodule
