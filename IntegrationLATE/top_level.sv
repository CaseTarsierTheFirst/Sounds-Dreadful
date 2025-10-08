module top_level #(
  parameter int DE1_SOC = 0 // !!!IMPORTANT: Set this to 1 for DE1 or 0 for DE2
) (
		input  wire        CLOCK_50,
		input  wire [17:0] SW,
		
		output wire        VGA_CLK,    
		output wire        VGA_HS,     
		output wire        VGA_VS,     
		output wire        VGA_BLANK_N,  
		output wire        VGA_SYNC_N,   
		output wire [7:0]  VGA_R,        
		output wire [7:0]  VGA_G,        
		output wire [7:0]  VGA_B,       
		
  // DE1-SoC I2C to WM8731:
  output         FPGA_I2C_SCLK,
  inout          FPGA_I2C_SDAT,
  // DE2-115 I2C to WM8731:
  output         I2C_SCLK,
  inout          I2C_SDAT,

  input          AUD_ADCDAT,
  input          AUD_BCLK,
  output         AUD_XCK,
  input          AUD_ADCLRCK,

  output  logic [17:0] LEDR,
  output logic [7:0]   LEDG,

  // =================== Additional Ports Here from stock ==============================
  input  logic [3:0]  KEY,   // use KEY[0] to capture noise (active-low)
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
  // ===================================================================================
);

  // Active-high run, low = reset (DE2 buttons are active-low)
  logic rst_n;
  assign rst_n = KEY[3];

  // Mic (48 kHz) -> Decimator (12 kHz) -> SNR
  localparam int N = 16;

  logic               mic_valid;
  logic signed [N-1:0] mic_sample;

  logic               decim_valid;
  logic signed [N-1:0] decim_sample;

  // LED fanout (mapped differently for DE1 vs DE2)
  logic [15:0] DE_LEDR;

  // Codec clocks
  logic adc_clk;  adc_pll adc_pll_u (.areset(1'b0), .inclk0(CLOCK_50), .c0(adc_clk)); // 18.432 MHz
  logic i2c_clk;  i2c_pll i2c_pll_u (.areset(1'b0), .inclk0(CLOCK_50), .c0(i2c_clk)); // ~20 kHz

  // Board-specific wiring
  generate
    if (DE1_SOC) begin : DE1_SOC_VS_DE2_115_CHANGES
      set_audio_encoder set_codec_de1_soc (.i2c_clk(i2c_clk), .I2C_SCLK(FPGA_I2C_SCLK), .I2C_SDAT(FPGA_I2C_SDAT));
      assign LEDR[9:0]   = DE_LEDR[15:6]; // 10 MSBs to the 10 LEDs
      assign LEDR[17:10] = 8'hFF;         // tie-off
      assign I2C_SCLK = 1'b1;
      assign I2C_SDAT = 1'bZ;
    end else begin
      set_audio_encoder set_codec_de2_115 (.i2c_clk(i2c_clk), .I2C_SCLK(I2C_SCLK), .I2C_SDAT(I2C_SDAT));
      assign LEDR = {2'b0, DE_LEDR};      // use all 16 data bits; pad to 18
      assign FPGA_I2C_SCLK = 1'b1;        // tie-off
      assign FPGA_I2C_SDAT = 1'bZ;
    end
  endgenerate

  // ======================== Mic capture (48 kHz) ========================
  mic_load #(.N(N)) u_mic_load (
    .adclrc      (AUD_ADCLRCK),
    .bclk        (AUD_BCLK),
    .adcdat      (AUD_ADCDAT),
    .valid       (mic_valid),
    .sample_data (mic_sample)
  );

  assign AUD_XCK = adc_clk;

  // ======================== Decimator (÷4 to ~12 kHz) ===================
  logic decim_x_ready;
  decimate #(.W(N), .DECIMATE_FACTOR(4)) u_decim (
    .clk     (AUD_BCLK),
    .x_valid (mic_valid),
    .x_ready (decim_x_ready),
    .x_data  (mic_sample),
    .y_valid (decim_valid),
    .y_ready (1'b1),
    .y_data  (decim_sample)
  );

  // ======================== SNR calculator ===============================
  logic [7:0]  snr_db;
  logic [15:0] sig_rms, noise_rms;
  logic        snr_valid;

  snr_calculator #(
    .DATA_WIDTH (N),
    .SNR_WIDTH  (8),
    .SIG_SHIFT  (6),    // fast MA
    .NOISE_SHIFT(12)    // slow MA (only while quiet_period=1)
  ) u_snr (
    .clk               (AUD_BCLK),
    .reset             (~rst_n),
    .quiet_period      (~KEY[0]),
    .audio_input       (decim_sample),
    .audio_input_valid (decim_valid),
    .audio_input_ready (),
    .snr_db            (snr_db),
    .signal_rms        (sig_rms),
    .noise_rms         (noise_rms),
    .output_valid      (snr_valid),
    .output_ready      (1'b1),

    // passthrough (unused here)
    .bpm_in            ('0),
    .bpm_valid_in      (1'b0),
    .bpm_out           (),
    .bpm_valid_out     ()
  );

  // ===== Small CDC to bring SNR from AUD_BCLK → CLOCK_50 =====
  // AUD_BCLK domain
  reg  [7:0] snr_db_aud;
  reg        snr_tgl_aud;
  always_ff @(posedge AUD_BCLK or negedge rst_n) begin
    if (!rst_n) begin
      snr_db_aud  <= 8'd0;
      snr_tgl_aud <= 1'b0;
    end else if (snr_valid) begin
      snr_db_aud  <= snr_db;
      snr_tgl_aud <= ~snr_tgl_aud;
    end
  end

  // CLOCK_50 domain
  reg  [2:0] snr_tgl_sync;
  wire       snr_strobe;
  reg  [7:0] snr_shadow;

  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) snr_tgl_sync <= 3'b000;
    else        snr_tgl_sync <= {snr_tgl_sync[1:0], snr_tgl_aud};
  end
  assign snr_strobe = snr_tgl_sync[2] ^ snr_tgl_sync[1];

  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) snr_shadow <= 8'd0;
    else if (snr_strobe) snr_shadow <= snr_db_aud;
  end

  // ============================ BPM Estimator ============================
  logic [15:0] beat_strength;
  logic [15:0] final_BPM_estimate;
  logic        beat_pulse;

  // debug wires used below (DECLARE THEM)
  logic [15:0] fft_input;
  logic [31:0] windowed_sample;
  logic [31:0] fft_real_out;
  logic [63:0] mag_sq;
  logic [73:0] flux_value;
  logic        mag_valid;
  logic        fft_input_valid, windowed_valid, fft_valid;
  logic        frame_done;
  logic [42:0] flux_accum;
  logic        flux_valid;
  logic        beat_valid;
  logic [1:0]  state_low;

  bpm_estimator_top_level #(
    .W(16),
    .NSamples(1024)
  ) u_bpm_estimator (
    .clk               (CLOCK_50),
    .reset             (~rst_n),
    .audio_clk         (AUD_BCLK),
    .audio_input_valid (decim_valid),
    .mic_stream        (decim_sample),

    .beat_pulse        (beat_pulse),
    .beat_strength     (beat_strength),
    .final_BPM_estimate(final_BPM_estimate), // BPM OUTPUT HERE 

    // debugging outputs
    .fft_input         (fft_input),
    .windowed_sample   (windowed_sample),
    .fft_real_out      (fft_real_out),
    .mag_sq            (mag_sq),
    .flux_value        (flux_value),
    .mag_valid         (mag_valid),
    .fft_input_valid   (fft_input_valid),
    .windowed_valid    (windowed_valid),
    .fft_valid         (fft_valid),
    .frame_done        (frame_done),
    .flux_accum        (flux_accum),
    .beat_valid        (beat_valid),
    .flux_valid        (flux_valid),
    .state_low         (state_low)
  );

  // ======================== LED debug (decimated stream) =================
  logic [15:0] abs_decim;
  always_comb begin
    abs_decim = decim_sample[15] ? (~decim_sample + 16'd1) : decim_sample;
  end
  always_ff @(posedge AUD_BCLK) begin
    DE_LEDR <= abs_decim;
  end

  // ----------------------------------------------------
  // Slow refresh divider (50 MHz → ~100 Hz refresh) for BPM, LEDs
  // ----------------------------------------------------
  localparam int REFRESH_DIV = 500_000;  // 50e6 / 5e5 = 100 Hz
  reg [18:0] refresh_cnt;
  reg        refresh_tick;

  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      refresh_cnt  <= '0;
      refresh_tick <= 1'b0;
    end else if (refresh_cnt == REFRESH_DIV-1) begin
      refresh_cnt  <= '0;
      refresh_tick <= 1'b1;
    end else begin
      refresh_cnt  <= refresh_cnt + 1'b1;
      refresh_tick <= 1'b0;
    end
  end

	// ---------- Slower SNR refresh (4 Hz @ 50 MHz) ----------
	localparam int SNR_REFRESH_DIV = 12_500_000;              // 50e6 / 4
	localparam int SNR_REF_W       = $clog2(SNR_REFRESH_DIV);
	reg [SNR_REF_W-1:0] snr_ref_cnt;
	reg                  snr_ref_tick;

	always_ff @(posedge CLOCK_50 or negedge rst_n) begin
	  if (!rst_n) begin
		 snr_ref_cnt  <= '0;
		 snr_ref_tick <= 1'b0;
	  end else if (snr_ref_cnt == SNR_REFRESH_DIV-1) begin
		 snr_ref_cnt  <= '0;
		 snr_ref_tick <= 1'b1;     // one-cycle pulse @ ~4 Hz
	  end else begin
		 snr_ref_cnt  <= snr_ref_cnt + 1'b1;
		 snr_ref_tick <= 1'b0;
	  end
	end

	// 4 Hz SNR latch (uses CDC'd snr_shadow)
	always_ff @(posedge CLOCK_50 or negedge rst_n) begin
	  if (!rst_n) begin
		 snr_slow <= 8'd0;
	  end else if (snr_ref_tick) begin
		 snr_slow <= snr_shadow;   // 0..99 (or more), shown on HEX4..HEX5
	  end
	end


  // ---------------- Latch BPM & SNR (separate rates) ----------------
  reg [15:0] bpm_slow;
  reg [7:0]  snr_slow;

  // 100 Hz BPM latch
  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      bpm_slow <= 16'd0;
    end else if (refresh_tick) begin
      bpm_slow <= final_BPM_estimate;   // 0..9999 OK, display takes 11 LSBs
    end
  end

  // ---------------- LED debug (throttled @100 Hz) ----------------
  reg [7:0] led_buf;
  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      led_buf <= 8'h00;
    end else if (refresh_tick) begin
      led_buf[0] <= flux_valid;
      led_buf[1] <= beat_valid;
      led_buf[2] <= state_low[0];
      led_buf[3] <= state_low[1];
      led_buf[4] <= windowed_valid;
      led_buf[5] <= fft_valid;
      led_buf[6] <= frame_done;
      led_buf[7] <= |flux_accum;
    end
  end
  assign LEDG = led_buf;

  // -------------------- BPM on HEX0..HEX3 --------------------
  display u_bpm_display (
    .clk      (CLOCK_50),
    .value    (bpm_slow[10:0]),  // display expects 11 bits
    .display0 (HEX0),
    .display1 (HEX1),
    .display2 (HEX2),
    .display3 (HEX3)
  );

  // -------------------- SNR on HEX4..HEX5 --------------------
  // We only show two digits; the display core produces 4 digits—drop the top two.
  wire [6:0] snr_unused2, snr_unused3;
  display u_snr_display (
    .clk      (CLOCK_50),
    .value    ({3'b000, snr_slow}),  // zero-extend 8-bit SNR to 11 bits
    .display0 (HEX4),                // ones
    .display1 (HEX5),                // tens
    .display2 (snr_unused2),
    .display3 (snr_unused3)
  );

  // Optional: blank HEX6/HEX7 (active-low segments on DE boards)
  localparam logic [6:0] BLANK = 7'b111_1111;
  assign HEX6 = BLANK;
  assign HEX7 = BLANK;
  
  vga u_vga (
		.clk_clk(CLOCK_50),
		.face_select_face_select(SW[1:0]),
		.final_bpm_estimate(final_BPM_estimate),
		.switch(SW[0]),
		.reset_reset_n(1'b1),
		.vga_CLK(VGA_CLK),
		.vga_HS(VGA_HS),
		.vga_VS(VGA_VS),
		.vga_BLANK(VGA_BLANK_N),
		.vga_SYNC(VGA_SYNC_N),
		.vga_R(VGA_R),
		.vga_G(VGA_G),
		.vga_B(VGA_B)
	);

endmodule

