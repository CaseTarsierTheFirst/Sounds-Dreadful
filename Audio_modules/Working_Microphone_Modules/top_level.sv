module top_level #(
  parameter int DE1_SOC = 0 // !!!IMPORTANT: Set this to 1 for DE1 or 0 for DE2
) (
  input  CLOCK_50,

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
  // 'mic_sample' and 'mic_valid' come straight from mic_load when a fresh sample is ready
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
    .y_ready (1'b1),          // always ready (no backpressure sink)
    .y_data  (decim_sample)
  );

  // ======================== SNR calculator ===============================
  // New SNR outputs
		logic [7:0]  snr_db;
		logic [15:0] sig_rms, noise_rms;
		logic        snr_valid, snr_ready;

	snr_calculator #(
		.DATA_WIDTH(N),
		.SNR_WIDTH(8)
		) u_snr (
		.clk             (AUD_BCLK),
		.reset           (~rst_n),          // new module expects active-high reset
		.quiet_period    (~KEY[0]),          // you can use KEY0 as “quiet” calibration
		.audio_input     (decim_sample),
		.audio_input_valid(decim_valid),
		.audio_input_ready(),               // not used, always ready
		.snr_db          (snr_db),
		.signal_rms      (sig_rms),
		.noise_rms       (noise_rms),
		.output_valid    (snr_valid),
		.output_ready    (1'b1)             // always consume results
		);


  // ======================== LED debug (decimated stream) =================
  // Show |decim_sample| on LEDs so you can confirm activity responds to sound.
  logic [15:0] abs_decim;
  always_comb begin
    abs_decim = decim_sample[15] ? (~decim_sample + 16'd1) : decim_sample;
  end
  always_ff @(posedge AUD_BCLK) begin
    DE_LEDR <= abs_decim;            // magnitude on LEDs (DE1 shows top 10 bits)
  end

  // ======================== Seven-segment display ========================
  // Active-low HEX on DE2-115; this shows two digits of snr_db
  logic [7:0] snr_db_latched;
logic [10:0] disp_cnt;  // enough bits for ~2000 counts

always_ff @(posedge AUD_BCLK) begin
  if (!rst_n) begin
    disp_cnt <= '0;
    snr_db_latched <= 8'd0;
  end else if (snr_valid) begin
    if (disp_cnt == 11'd4799) begin  // every ~100ms @12kHz valid rate
      snr_db_latched <= snr_db;
      disp_cnt <= 0;
    end else begin
      disp_cnt <= disp_cnt + 1;
    end
  end
end

  sevenseg_display8 #(.ACTIVE_LOW(1), .BLANK_LEADING_ZEROS(1)) u_hex8 (
    .value ({8'd0, snr_db_latched}), // 0000..00XX
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
    .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7)
  );

endmodule
