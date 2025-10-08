
module bpm_estimator_top_level #(
    parameter W = 16,
    parameter NSamples = 1024
)(
    //inputs
    input logic clk,
    input logic reset,
    input logic audio_clk,
    input logic audio_input_valid,
    input logic [W-1:0] mic_stream, //decimated mic stream value

    //outputs
    output     beat_pulse, //single-cycle pulse to indicate beat detected
    output     beat_strength, //integer representing detected beat amp
    output     [15:0] final_BPM_estimate, //integer representing current BPM estimate
	 
	 //debuggin outputs
	 output		[W-1:0] fft_input,
	 output     [2*W-1:0] windowed_sample,
	 output		[2*W-1:0] fft_real_out,
	 output		[4*W-1:0] mag_sq,
	 output     [73:0] flux_value,
	 output mag_valid,
	 output fft_input_valid,
	 output windowed_valid,
	 output fft_valid,
	 output frame_done,
	 output [42:0] flux_accum,
	 output beat_valid,
	 output flux_valid,
	 output [1:0] state_low
);
//Tasks:
//window audio input into frames
    //buffer N samples into RAM block (use ed lesson 4 1.3 FFT IP)
    //apply hanning window - multiply each smaple by precomputed coefficient from python code

//FIFO - hanning wires
//logic [W-1:0] fft_input;
//logic fft_input_valid;
logic fft_input_ready;
logic frame_ready;

fft_input_buffer #(.W(W), .NSamples(NSamples)) u_fifo_for_fft (
    .clk(clk),
    .reset(reset),
    .audio_clk(audio_clk),
    .audio_input_valid(audio_input_valid),
    .audio_input_ready(), //havent used yet
    .audio_input_data(mic_stream),
	 
    .fft_input(fft_input),
    .fft_input_valid(fft_input_valid),
	 //.fft_input_ready(fft_input_ready),
    //.frame_ready(frame_ready)
);

//Hanning Window
//logic [W-1:0] windowed_sample;
//logic windowed_valid;
//logic [9:0] sample_index;

assign fft_input_ready = 1'b1;

hanning_window #(.W(W), .N(NSamples), .MAX_SAMPLE_INDEX(9)) u_hanning_window (
    .clk(clk),
    .reset(reset),
    .sample_in(fft_input),
	 .sample_in_valid(fft_input_valid),
	 .sample_in_ready(fft_input_ready),
    //.sample_index(sample_index),
    .windowed_sample(windowed_sample),
	 .windowed_valid(windowed_valid)
);



//compute magnitude spectrum on each frame as soon as it becomes available
    //use FFT IP core to compute magnitude spectrum
    //should pipeline this
	 
//logic fft_valid;
//logic [2*W-1:0] fft_real_out;
logic [31:0] fft_imag_out;

FFT #(
    .WIDTH(32)
) fft_inst (
    .clock(clk),
    .reset(reset),
    .di_en(windowed_valid),   // 1-cycle pulse when input is valid - input data enable
    .di_re(windowed_sample),      // 32-bit real input from Hanning window
    .di_im(32'd0),   // must use zeroes for imaginary part
    .do_en(fft_valid),           // output valid pulse
    .do_re(fft_real_out),        // real part of FFT output
    .do_im(fft_imag_out)         // imaginary part of FFT output
);

//logic [31:0] mag_sq;
//logic mag_valid;

fft_mag_sq #(.W(32)) u_mag_spec (
    //magnitude computation inputs
    .clk(clk),
    .reset(reset),
    .fft_valid(fft_valid),
    .fft_real(fft_real_out),
    .fft_imag(fft_imag_out),

    //magnitude computation outputs
    .mag_sq(mag_sq),
    .mag_valid(mag_valid)
);

//compute spectral flux (sum of positive changes per frequency bin in magnitude spectrum over 2 consecutive frames over time)
    //for each bin, sum over bins or bands
//band-selective mapping: split up flux into 3 separate frequency bands to create BPM measurement for each band
    //divide bins into low/mid/high freq. bands, tracking flux per band

//logic [9:0] bin_index;
//logic frame_done;
//logic [42:0] flux_value;
//logic flux_valid;

logic [73:0] flux_low;
logic [73:0] flux_mid;
logic [73:0] flux_high;
//logic beat_valid;



//always_ff @(posedge clk) begin
//    if (reset) begin
//        bin_index <= 0;
//        frame_done <= 0;
//    end
//    else if (mag_valid) begin
//        if (bin_index == NSamples - 1) begin
//            frame_done <= 1;
//            bin_index <= 0;
//        end
//        else begin
//            frame_done <= 0;
//            bin_index <= bin_index + 1;
//        end
//    end
//    else begin
//        frame_done <= 0;
//    end
//end

spectral_flux #(.W(64), .N(1024)) u_spectral_flux (
    .clk(clk),
    .reset(reset),
    .mag_valid(mag_valid),
    .mag_sq(mag_sq),
    //.bin_index(bin_index),
    //.frame_done(frame_done),
    .flux_value(flux_value),
    .flux_low(flux_low),
    .flux_mid(flux_mid),
    .flux_high(flux_high),
    .flux_valid(flux_valid),
    .beat_valid(beat_valid),
	 //debugging outputs
	 .flux_accum(flux_accum),
	 .frame_done(frame_done)
);

//perform autocorrelation method on each spectral flux band to estimate period between beats for each frequency band
    //store flux values over time, compute autocorrelation to find periodicity, peak in autocorrelation gives beat
    //can be approximated with sliding dot product apparently

logic [15:0] bpm_low, bpm_mid, bpm_high;
logic bpm_valid_low, bpm_valid_mid, bpm_valid_high;

autocorrelation #(.W(70), .N(32), .SAMPLE_RATE(12000), .FRAME_SIZE(1024))
                u_auto_low (
                    .clk(clk),
                    .reset(reset),
						  .flux_in(flux_low),
                    .flux_valid(flux_valid),
                    .beat_valid(beat_valid),
                    .BPM_estimate(bpm_low),
                    .bpm_valid(bpm_valid_low),
						  .state_out (state_low)
//						  .FRAME_SIZE(256),   // equals the HOP size
//						  .FRAC_BITS(12)
                );
					 

autocorrelation #(.W(70), .N(32), .SAMPLE_RATE(12000), .FRAME_SIZE(1024))
                u_auto_mid (
                     .clk(clk),
                    .reset(reset),
                    .flux_valid(flux_valid),
						  .flux_in(flux_mid),
                    .beat_valid(beat_valid),
                    .BPM_estimate(bpm_mid),
                    .bpm_valid(bpm_valid_mid)
//						  .FRAME_SIZE(256),   // equals the HOP size
//						  .FRAC_BITS(12)
                );

autocorrelation #(.W(70), .N(32), .SAMPLE_RATE(12000), .FRAME_SIZE(1024))
                u_auto_high (
                     .clk(clk),
                    .reset(reset),
                    .flux_valid(flux_valid),
						  .flux_in(flux_high),
                    .beat_valid(beat_valid),
                    .BPM_estimate(bpm_high),
                    .bpm_valid(bpm_valid_high)
//						  .FRAME_SIZE(256),   // equals the HOP size
//                    .FRAC_BITS(12)
                );

//period between beats is related to BPM via simple formula
//assign final_BPM_estimate = /*bpm_low;*/ (3*bpm_low + 1*bpm_mid + 3*bpm_high) / 5; //weight it to low bands - can tune and adjust this obviously
//probably can even weight it towards something like the actual spectral flux magnitudes or like the confidence of the peaks idk - let's get it working first



assign final_BPM_estimate = (2*bpm_low + 2*bpm_mid + 1*bpm_high) / 5;
endmodule
