`timescale 1ns/1ns

module tb_spectral_flux;

    localparam W = 16;
    localparam N = 8;
    localparam MAX_FLUX_LENGTH = 32;
    localparam CLK_PERIOD = 10;

    logic clk, reset;
    logic mag_valid;
    logic [W-1:0] mag_sq;

    logic [MAX_FLUX_LENGTH-1:0] flux_value;
    logic [MAX_FLUX_LENGTH-1:0] flux_low, flux_mid, flux_high;
    logic flux_valid, beat_valid, frame_done;
    logic [MAX_FLUX_LENGTH-1:0] flux_accum;

    spectral_flux #(
        .W(W), .N(N), .MAX_FLUX_LENGTH(MAX_FLUX_LENGTH)
    ) dut (
        .clk(clk),
        .reset(reset),
        .mag_valid(mag_valid),
        .mag_sq(mag_sq),
        .flux_value(flux_value),
        .flux_valid(flux_valid),
        .beat_valid(beat_valid),
        .frame_done(frame_done),
        .flux_low(flux_low),
        .flux_mid(flux_mid),
        .flux_high(flux_high),
        .flux_accum(flux_accum)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Send N samples with constant magnitude (should produce 0 accumulation)
    task send_constant_frame(input [W-1:0] value);
        begin
            for (int i = 0; i < N; i++) begin
                @(posedge clk);
                mag_valid <= 1;
                mag_sq <= value;
            end
            @(posedge clk);
            mag_valid <= 0;
        end
    endtask

    // Send N samples with increasing magnitude (should produce accumulation)
    task send_ramp_frame(input [W-1:0] start, input [W-1:0] step);
        begin
            for (int i = 0; i < N; i++) begin
                @(posedge clk);
                mag_valid <= 1;
                mag_sq <= start + i * step;
            end
            @(posedge clk);
            mag_valid <= 0;
        end
    endtask

    initial begin
        // Init
        reset = 1;
        mag_valid = 0;
        mag_sq = 0;
        #(5 * CLK_PERIOD);
        reset = 0;

        // Frame 1: Constant -> should output 0 flux
        $display("=== Frame 1: Constant (no change) ===");
        send_constant_frame(16'd500);
        #(5 * CLK_PERIOD);

        // Frame 2: Increasing values
        $display("=== Frame 2: Ramp (positive diff) ===");
        send_ramp_frame(16'd100, 16'd50);
        #(5 * CLK_PERIOD);

        // Frame 3: Mixed bands
        $display("=== Frame 3: Band spread ===");
        for (int i = 0; i < N; i++) begin
            @(posedge clk);
            mag_valid <= 1;
            case (i % 3)
                0: mag_sq <= 16'd100;   // low
                1: mag_sq <= 16'd700;   // mid
                2: mag_sq <= 16'd1500;  // high
            endcase
        end
        @(posedge clk);
        mag_valid <= 0;
        #(5
