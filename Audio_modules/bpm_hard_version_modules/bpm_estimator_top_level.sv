module bpm_estimator_top_level(
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
    output     final_BPM_estimate //integer representing current BPM estimate
);

//Tasks:
//window audio input into frames
    //buffer N samples into RAM block (use ed lesson 4 1.3 FFT IP)
    //apply hanning window - multiply each smaple by precomputed coefficient from python code

logic [W-1:0] fft_input;
logic fft_input_valid;
logic frame_ready;

fft_input_buffer #(.W(W), .NSamples(NSamples)) u_fifo_for_fft (
    .clk(clk),
    .reset(reset),
    .audio_clk(audio_clk),
    .audio_input_valid(audio_input_valid),
    .audio_input_ready(audio_input_ready), //havent used yet
    .audio_input_data(mic_stream),
    .fft_input(fft_input),
    .fft_input_valid(fft_input_valid),
    .frame_ready(frame_ready)
);

logic [W+15:0] windowed_sample;
logic [9:0] sample_index;

hanning_window #(.W(W), .N(NSamples), .MAX_SAMPLE_INDEX(9)) u_hanning_window (
    .clk(clk),
    .reset(reset),
    .sample_in(fft_input),
    .sample_index(sample_index),
    .windowed_sample(windowed_sample)
);

//read values from FIFO and pass them through Hanning Window
always_ff @(posedge clk) begin
    if (reset) begin
        sample_index <= 0;
    end
    else if (fft_input_valid) begin
        sample_index <= sample_index + 1;
    end
end

//compute magnitude spectrum on each frame as soon as it becomes available
    //use FFT IP core to compute magnitude spectrum
    //should pipeline this

logic [15:0] fft_sink_real, fft_sink_imag;
logic fft_sink_valid, fft_sink_sop, fft_sink_eop;
logic fft_sink_ready; //for backpressure

logic [15:0] fft_out_real, fft_out_imag;
logic fft_out_valid;

assign fft_sink_real = windowed_sample[W+15:16]; //real part of input sample
assign fft_sink_imag = 16'd0; //imaginary part - set to 0 fro real signals
assign fft_sink_valid = fft_input_valid; //when input sample is valid
assign fft_sink_sop = (sample_index == 0); //start of packet - assert on first sample of frame
assign fft_sink_eop = (sample_index == NSamples-1); //end of packet - assert on last sample of frame

//instantiating HARD IP FFT
hard_ip_fft u_fft (
    //Inputs to FFT
    .clk(clk),
    .reset_n(~reset),
    .sink_valid(fft_sink_valid),
    .sink_ready(fft_sink_ready),
    .sink_sop(fft_sink_sop),
    .sink_eop(fft_sink_eop),
    .sink_real(fft_sink_real),
    .sink_imag(fft_sink_imag),
    .fftpts_in(NSamples),
    //outputs from FFT
    .source_valid(fft_out_valid),
    .source_real(fft_out_real),
    .source_imag(fft_out_imag),
    .source_sop(),
    .source_eop()
);

logic [31:0] mag_sq;
logic mag_valid;

fft_mag_sq #(.W(16)) u_mag_spec (
    //magnitude computation inputs
    .clk(clk),
    .reset(reset),
    .fft_valid(fft_out_valid),
    .fft_real(fft_out_real),
    .fft_imag(fft_out_imag),

    //magnitude computation outputs
    .mag_sq(mag_sq),
    .mag_valid(mag_valid)
);

//compute spectral flux (sum of positive changes per frequency bin in magnitude spectrum over 2 consecutive frames over time)
    //for each bin, sum over bins or bands
//band-selective mapping: split up flux into 3 separate frequency bands to create BPM measurement for each band
    //divide bins into low/mid/high freq. bands, tracking flux per band

logic [9:0] bin_index;
logic frame_done;
logic [42:0] flux_value;
logic flux_valid;

logic [42:0] flux_low;
logic [42:0] flux_mid;
logic [42:0] flux_high;
logic beat_valid;

always_ff @(posedge clk) begin
    if (reset) begin
        bin_index <= 0;
        frame_done <= 0;
    end
    else if (mag_valid) begin
        if (bin_index == NSamples - 1) begin
            frame_done <= 1;
            bin_index <= 0;
        end
        else begin
            frame_done <= 0;
            bin_index <= bin_index + 1;
        end
    end
    else begin
        frame_done <= 0;
    end
end

spectral_flux #(.W(32), .N(1024)) u_spectral_flux (
    .clk(clk),
    .reset(reset),
    .mag_valid(mag_valid),
    .mag_sq(mag_sq),
    .bin_index(bin_index),
    .frame_done(frame_done),
    .flux_value(flux_value),
    .flux_low(flux_low),
    .flux_mid(flux_mid),
    .flux_high(flux_high),
    .flux_valid(flux_valid),
    .beat_valid(beat_valid)
);

//perform autocorrelation method on each spectral flux band to estimate period between beats for each frequency band
    //store flux values over time, compute autocorrelation to find periodicity, peak in autocorrelation gives beat
    //can be approximated with sliding dot product apparently

logic [15:0] bpm_low, bpm_mid, bpm_high;
logic bpm_valid_low, bpm_valid_mid, bpm_valid_high;

autocorrelation #(.W(32), .N(64), .MIN_LAG(20), .MAX_LAG(200), .SAMPLE_RATE(8000), .FRAME_SIZE(1024))
                u_auto_low (
                    .clk(clk),
                    .reset(reset),
                    .flux_valid(flux_valid),
                    .beat_valid(beat_valid),
                    .BPM_estimate(bpm_low),
                    .bpm_valid(bpm_valid_low)
                );

autocorrelation #(.W(32), .N(64), .MIN_LAG(20), .MAX_LAG(200), .SAMPLE_RATE(8000), .FRAME_SIZE(1024))
                u_auto_mid (
                     .clk(clk),
                    .reset(reset),
                    .flux_valid(flux_valid),
                    .beat_valid(beat_valid),
                    .BPM_estimate(bpm_mid),
                    .bpm_valid(bpm_valid_mid)
                );

autocorrelation #(.W(32), .N(64), .MIN_LAG(20), .MAX_LAG(200), .SAMPLE_RATE(8000), .FRAME_SIZE(1024))
                u_auto_high (
                     .clk(clk),
                    .reset(reset),
                    .flux_valid(flux_valid),
                    .beat_valid(beat_valid),
                    .BPM_estimate(bpm_high),
                    .bpm_valid(bpm_valid_high)
                );

//period between beats is related to BPM via simple formula
assign final_BPM_estimate = (2*bpm_low + bpm_mid + bpm_hight) / 4; //weight it to low bands - can tune and adjust this obviously
//probably can even weight it towards something like the actual spectral flux magnitudes or like the confidence of the peaks idk - let's get it working first
    
endmodule
