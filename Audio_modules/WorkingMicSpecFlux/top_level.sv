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
  output logic [7:0] LEDG,

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
  
  
    //============================BPM Estimator=====================
  logic [15:0] beat_strength;
  logic [15:0] final_BPM_estimate;
  logic        beat_pulse;
  
  logic [15:0] fft_input;
  logic [31:0] windowed_sample;
  logic [31:0] fft_real_out;
  logic [63:0] mag_sq;
  logic [73:0] flux_value;
  logic mag_valid;
  
  logic frame_done;
  logic [42:0] flux_accum;
  logic flux_valid;
  logic beat_valid;
  logic [1:0] state_low;

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
    .final_BPM_estimate(final_BPM_estimate),
	 //debugging outputs
	 .fft_input (fft_input),
	 .windowed_sample (windowed_sample),
	 .fft_real_out (fft_real_out),
	 .mag_sq (mag_sq),
	 .flux_value (flux_value),
	 .mag_valid (mag_valid),
	 .fft_input_valid (fft_input_valid),
	 .windowed_valid (windowed_valid),
	 .fft_valid (fft_valid),
	 .frame_done (frame_done),
	 .flux_accum (flux_accum),
	 .beat_valid (beat_valid),
	 .flux_valid (flux_valid),
	 .state_low (state_low)
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
  
    // ======================== Seven-seg display ========================
  // Latch BPM every ~200 ms so HEX is stable on CLOCK_50
//  logic [15:0] bpm_latched;
//  logic [25:0] tick_200ms;  // 50e6 * 0.2s ≈ 10_000_000
//
//  always_ff @(posedge CLOCK_50) begin
//    if (!rst_n) begin
//      tick_200ms  <= '0;
//      bpm_latched <= 16'd0;
//    end else begin
//      if (tick_200ms == 26'd10_000_00) begin
//        bpm_latched <= final_BPM_estimate;
//        tick_200ms  <= 0;
//      end else begin
//        tick_200ms <= tick_200ms + 1;
//      end
//    end
//  end
//
//  // Use your existing 8-digit driver: [HEX7..HEX0] = [S][R][SNRt][SNRun][BPM thou][BPM hund][BPM tens][BPM ones]
//  sevenseg_snr_bpm #(
//    .ACTIVE_LOW(1),
//    .BLANK_LEADING_ZEROS(1)
//  ) u_hex8 (
//    .snr_val (8'd0),          // tie SNR to 0 for now
//    .bpm_val (fft_input),
//    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
//    .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7)
//  );

//	display u_display (
//		.clk(CLOCK_50),
//		.value(flux_value),
//		.display0(HEX0),
//		.display1(HEX1),
//		.display2(HEX2),
//		.display3(HEX3)
//	);

//	reg [23:0] hb;
//	always_ff @(posedge CLOCK_50) begin
//		if (~rst_n) begin
//			hb <= 0;
//		end
//		else if (mag_valid) begin
//			hb <= hb + 1;
//		end
//	end
//	assign LEDG[0] = hb[23];

	//bin to hex to display on 7-segs
//	reg [9:0] bin_cnt;
//	always_ff @(posedge CLOCK_50) begin
//	  if (~rst_n) bin_cnt <= 0;
//	  else if (mag_valid) bin_cnt <= (bin_cnt==1023) ? 10'd0 : bin_cnt + 10'd1;
//	end
//	  
//	assign LEDG[0] = mag_valid;
//   assign LEDG[1] = |mag_sq[31:0];     // any activity out of mag block?
//	assign LEDG[2] = |flux_value;       // ever nonzero after a frame?
//	//assign LEDG[3] = flux_valid;        // pulses once per frame
//	
//	assign LEDG[3] = fft_input_valid;
//	assign LEDG[4] = windowed_valid;
//	assign LEDG[5] = fft_valid;
//	
//	assign LEDG[6] = frame_done;
//	assign LEDG[7] = flux_accum;
	  
  
  
  // ----------------------------------------------------
// Slow refresh divider (50 MHz → ~100 Hz refresh)
// ----------------------------------------------------
localparam int REFRESH_DIV = 500_0000;  // 50e6 / 500k = 100 Hz
reg [22:0] refresh_cnt;                // big enough for REFRESH_DIV
reg        refresh_tick;

always_ff @(posedge CLOCK_50 or negedge rst_n) begin
  if (!rst_n) begin
    refresh_cnt  <= '0;
    refresh_tick <= 1'b0;
  end else if (refresh_cnt == REFRESH_DIV-1) begin
    refresh_cnt  <= '0;
    refresh_tick <= 1'b1;   // one-cycle pulse every 100 Hz
  end else begin
    refresh_cnt  <= refresh_cnt + 1'b1;
    refresh_tick <= 1'b0;
  end
end
reg [7:0] led_buf;

always_ff @(posedge CLOCK_50 or negedge rst_n) begin
  if (!rst_n) begin
    led_buf <= 8'h00;
  end else if (refresh_tick) begin
    led_buf[0] <= flux_valid; //mag_valid;
    led_buf[1] <= beat_valid; //|mag_sq;
    led_buf[2] <= state_low[0]; //|flux_value;
    led_buf[3] <= state_low[1];//fft_input_valid;
    led_buf[4] <= windowed_valid;
    led_buf[5] <= fft_valid;
    led_buf[6] <= frame_done;
    led_buf[7] <= |flux_accum;
  end
end

assign LEDG = led_buf;

// ----------------------------------------------------
// Throttled copy of flux_value for display
// ----------------------------------------------------
reg [31:0] value_slow;

always_ff @(posedge CLOCK_50 or negedge rst_n) begin
  if (!rst_n) begin
    value_slow <= 32'd0;
  end else if (refresh_tick) begin
    value_slow <= final_BPM_estimate;
  end
end

// ----------------------------------------------------
// Display instance (UNCHANGED)
// ----------------------------------------------------
display u_display (
    .clk(CLOCK_50),
    .value(final_BPM_estimate),   // just replace with the slow version
    .display0(HEX0),
    .display1(HEX1),
    .display2(HEX2),
    .display3(HEX3)
);


  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  

  // ======================== Seven-segment display ========================
  // latch SNR every ~100 ms for display
//logic [7:0] snr_db_latched;
//logic [10:0] disp_cnt;
//
//always_ff @(posedge AUD_BCLK) begin
//  if (!rst_n) begin
//    disp_cnt <= '0;
//    snr_db_latched <= 8'd0;
//  end else if (snr_valid) begin
//    if (disp_cnt == 11'd4799) begin  // every ~100ms @12kHz valid rate
//      snr_db_latched <= snr_db;
//      disp_cnt <= 0;
//    end else begin
//      disp_cnt <= disp_cnt + 1;
//    end
//  end
//end
//
//// NEW: combined SNR + BPM display
//sevenseg_snr_bpm #(
//  .ACTIVE_LOW(1),
//  .BLANK_LEADING_ZEROS(1)
//) u_hex8 (
//  .snr_val (snr_db_latched),  // 0..99 SNR
//  .bpm_val (bpm_estimate),    // 0..9999 BPM
//  .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
//  .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7)
//);


endmodule
