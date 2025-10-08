module spectral_flux #(
    parameter N = 1024,     //Number of samples in each frame ("window")
    parameter W = 64,       //width of mag_sq
    parameter BIN_LENGTH = 10, 
    parameter MAX_FLUX_LENGTH = 70,
    parameter PREV_FRAMES_SPEC_FLUX = 32
)(
    input  logic clk,
    input  logic reset,
    input  logic mag_valid,
    input  logic [W-1:0] mag_sq,

    output logic [MAX_FLUX_LENGTH - 1:0] flux_value,
    output logic flux_valid,

    output logic [MAX_FLUX_LENGTH - 1:0] flux_low,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_mid,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_high,
    output logic beat_valid,
	 
    //debugging outputs
    output logic frame_done,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_accum
);

    // Internal counters
    logic [BIN_LENGTH-1:0] counter;      // sample index within frame
    logic frame_edge1, frame_edge2;
    logic edge_detect_frame_done;

    // Sequential read/write of prev_mag in BRAM
    (* ramstyle = "M9K" *) logic [W-1:0] prev_mag [0:N-1];
    logic [W-1:0] prev_val;
    logic signed [W-1:0] diff;
    logic [W-1:0] pos_diff;

    // Band accumulators
    logic [MAX_FLUX_LENGTH-1:0] accum_low, accum_mid, accum_high;

    // Sequential flux history buffer in BRAM
    (* ramstyle = "M9K" *) logic [MAX_FLUX_LENGTH-1:0] flux_history [0:PREV_FRAMES_SPEC_FLUX-1];
    logic [$clog2(PREV_FRAMES_SPEC_FLUX)-1:0] flux_index;
    logic [MAX_FLUX_LENGTH-1:0] flux_sum;
    logic [MAX_FLUX_LENGTH-1:0] flux_mean;
    logic [MAX_FLUX_LENGTH-1:0] threshold;

    // Frame-done edge detection
    always_ff @(posedge clk) begin
        frame_edge1 <= frame_done;
        frame_edge2 <= frame_edge1;
    end
    assign edge_detect_frame_done = (frame_edge1 && !frame_edge2);

    // Sequential accumulation control
    logic flushing;
    logic [$clog2(N):0] acc_index;

    // Sample counter per frame
    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            frame_done <= 0;
        end else if (mag_valid) begin
            if (counter == N-1) begin
                counter <= 0;
                frame_done <= 1;
            end else begin
                counter <= counter + 1;
                frame_done <= 0;
            end
        end
    end

    // Sequential flux accumulation (1 sample per cycle)
    always_ff @(posedge clk) begin
        if (reset) begin
            flux_accum <= 0;
            accum_low <= 0;
            accum_mid <= 0;
            accum_high <= 0;
            acc_index <= 0;
            flushing <= 0;
        end
        else if (edge_detect_frame_done) begin
            // Start flushing frame to accumulate flux sequentially
            acc_index <= 0; //changed
            flux_accum <= 0;
            accum_low <= 0;
            accum_mid <= 0;
            accum_high <= 0;
            flushing <= 1;
        end
        else if (flushing) begin
            // Read previous magnitude from BRAM
            prev_val <= prev_mag[acc_index];

            // Compute positive difference
            diff <= mag_sq; // placeholder, we will feed mag_sq sequentially externally
            pos_diff <= (diff[W-1] == 1'b0) ? diff : 0;

            // Accumulate total flux
            flux_accum <= flux_accum + pos_diff;

            // Accumulate bands
            if (diff < 512) accum_low <= accum_low + pos_diff;
            else if (diff < 1024) accum_mid <= accum_mid + pos_diff;
            else accum_high <= accum_high + pos_diff;

            // Update previous magnitude
            prev_mag[acc_index] <= diff;

            // Increment sequential accumulator index
            if (acc_index == N-1) begin
                flushing <= 0; // finished frame
            end else begin
                acc_index <= acc_index + 1;
            end
        end
    end

    // Flux valid and frame outputs
    logic [4:0] counter_valid;
    always_ff @(posedge clk) begin
        if (reset) begin
            flux_value <= 0;
            flux_low <= 0;
            flux_mid <= 0;
            flux_high <= 0;
            flux_valid <= 0;
            beat_valid <= 0;
            counter_valid <= 0;
            flux_sum <= 0;
            flux_index <= 0;
            threshold <= 0;
        end
        else if (!flushing && edge_detect_frame_done) begin
            // Send outputs after sequential accumulation
            flux_value <= flux_accum;
            flux_low <= accum_low;
            flux_mid <= accum_mid;
            flux_high <= accum_high;
            flux_valid <= 1;
            counter_valid <= 5;

            // Update moving mean
            flux_sum <= flux_sum - flux_history[flux_index] + flux_accum;
            flux_history[flux_index] <= flux_accum;
            flux_index <= (flux_index == PREV_FRAMES_SPEC_FLUX-1) ? 0 : flux_index + 1;

            flux_mean <= flux_sum / PREV_FRAMES_SPEC_FLUX;
            threshold <= flux_mean << 3;

            beat_valid <= (flux_accum > threshold) ? 1 : 0;
        end
        else begin
            if (counter_valid != 0) counter_valid <= counter_valid - 1;
            else flux_valid <= 0;
            if (counter_valid == 0) beat_valid <= 0;
        end
    end

endmodule
