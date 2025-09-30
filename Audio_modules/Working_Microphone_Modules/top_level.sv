module top_level #(
	parameter int DE1_SOC=0 // !!!IMPORTANT: Set this to 1 for DE1 or 0 for DE2
) (
	input CLOCK_50,

	// DE1-SoC I2C to WM8731:
	output         FPGA_I2C_SCLK,
	inout          FPGA_I2C_SDAT,
	// DE2-115 I2C to WM8731:
	output         I2C_SCLK,
	inout          I2C_SDAT,

	input         AUD_ADCDAT,
	input         AUD_BCLK,
	output        AUD_XCK,
	input         AUD_ADCLRCK,

	output  logic [17:0] LEDR,
	
	// =================== Additional Ports Here from stock ==============================
	
	input  logic [3:0]  KEY,              // use KEY[0] to capture noise (active-low)
	output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
	
	// ===================================================================================
);

	logic rst_n;
	assign rst_n = KEY[3];  // DE2 buttons are active-low; 1 = not pressed
	
	// Mic (48 kHz) -> Decimator (12 kHz) -> SNR
	localparam int N = 16;

	logic              mic_valid;
	logic signed [N-1:0] mic_sample;

	logic              decim_valid;
	logic signed [N-1:0] decim_sample;
	
	logic [15:0] DE_LEDR; // Accounts for the different number of LEDs on the DE1-Soc vs. DE2-115.

	logic adc_clk; adc_pll adc_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(adc_clk)); // generate 18.432 MHz clock
	logic i2c_clk; i2c_pll i2c_pll_u (.areset(1'b0),.inclk0(CLOCK_50),.c0(i2c_clk)); // generate 20 kHz clock
	
	
	generate
		if (DE1_SOC) begin : DE1_SOC_VS_DE2_115_CHANGES
			set_audio_encoder set_codec_de1_soc (.i2c_clk(i2c_clk), .I2C_SCLK(FPGA_I2C_SCLK), .I2C_SDAT(FPGA_I2C_SDAT)); // Connected to the DE1-SoC I2C pins
			assign LEDR[9:0]   = DE_LEDR[15:6]; // Take the 10 most significant data bits for the 10x DE1-SoC LEDs (pad the left 8 with zeros)
			assign LEDR[17:10] = 8'hFF; // Tie-off these unecessary ports to one
			assign I2C_SCLK = 1'b1;
			assign I2C_SDAT = 1'bZ;
		end else begin
			set_audio_encoder set_codec_de2_115 (.i2c_clk(i2c_clk), .I2C_SCLK(I2C_SCLK), .I2C_SDAT(I2C_SDAT)); // Connected to the DE2-115 I2C pins
			assign LEDR = {2'b0, DE_LEDR}; // Use all 16 data bits for the 18x DE2-115 LEDs (pad the left with 2x zeros)
			assign FPGA_I2C_SCLK = 1'b1; // Tie-off these unecessary ports to one
			assign FPGA_I2C_SDAT = 1'bZ;
		end
	endgenerate

	logic [15:0] data;
		
    mic_load #(.N(16)) u_mic_load (
      .adclrc(AUD_ADCLRCK),
      .bclk(AUD_BCLK),
      .adcdat(AUD_ADCDAT),
		.valid(mic_valid),
      .sample_data(data)
	);
	
	assign AUD_XCK = adc_clk;
		
	always_comb begin
		if (data[15]) DE_LEDR <= (~data + 1); // magnitude of a negative number (2's complement).
		else DE_LEDR <= data;
	end
	
	
	// ======================== ADDED LOGIC (SNR + 7-seg) ========================
	// Sample-valid strobe from LRCK (one pulse per new left sample)
	logic lrck_q;
	always_ff @(posedge AUD_BCLK) lrck_q <= AUD_ADCLRCK;
	wire samp_valid = (AUD_ADCLRCK & ~lrck_q); // rising-edge detect

	// SNR calculation (requires snr_calc.sv in your project)
	logic [7:0] snr_db;
	snr_calc #(.N(16), .EMA_SHIFT(10)) u_snr (
		.clk         (AUD_BCLK),
		.rst_n       (rst_n),        // <-- NEW
		.valid       (decim_valid),
		.sample_data (decim_sample),
		.KEY0        (KEY[0]),
		.snr_db      (snr_db)
	);
	
	
	// ======================== Decimator =========================================
		
		decimate #(.W(N), .DECIMATE_FACTOR(4)) u_decim (
			.clk     (AUD_BCLK),

			.x_valid (mic_valid),
			.x_ready (decim_x_ready),
			.x_data  (mic_sample),

			.y_valid (decim_valid),
			.y_ready (1'b1),        // always ready to accept decimated samples
			.y_data  (decim_sample)
		);
	
	
	
	


	// Seven-segment display (requires sevenseg_display.sv)
	// DE2-115 HEX are active-low, so keep ACTIVE_LOW=1
// snr_db is your 0..99 output from snr_calc
	sevenseg_display8 #(.ACTIVE_LOW(1), .BLANK_LEADING_ZEROS(1)) u_hex8 (
		.value ({8'd0, snr_db}), // widen to 16 bits; shows as 00XX
		.HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
		.HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7)
	);

	// =============================================================================
	
	
	
	

endmodule
