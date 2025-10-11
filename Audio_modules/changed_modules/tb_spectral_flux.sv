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
        .flux_accum() // optional, for debug
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task send_frame(input [W-1:0] base, input [W-1:0] step);
        for (int i = 0; i < N; i++) begin
            @(posedge clk);
            mag_valid <= 1;
            mag_sq <= base + step * i;
        end
        @(posedge clk);
        mag_valid <= 0;
    endtask

    task band_frame();
        for (int i = 0; i < N; i++) begin
            @(posedge clk);
            mag_valid <= 1;
            case (i % 3)
                0: mag_sq <= 16'd100;
                1: mag_sq <= 16'd700;
                2: mag_sq <= 16'd1400;
            endcase
        end
        @(posedge clk);
        mag_valid <= 0;
    endtask

    initial begin
        // Init
        reset = 1;
        mag_valid = 0;
        mag_sq = 0;
        #(5 * CLK_PERIOD);
        reset = 0;

        $display("=== Frame 1: Flat 200 ===");
        send_frame(200, 0);
        #(5 * CLK_PERIOD);

        $display("=== Frame 2: Ramp 100 +20 ===");
        send_frame(100, 20);
        #(
