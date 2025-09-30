/*
This is mostly based of Lesson 4 Ed: computes magnitude of each signal 
outputted from FFT. So, after the hanning window we feed it into the HARD IP FFT. Then we compute the magnitude squared which 
we will use for computing spectral flux and distributing frequency bands. This is basically identical to Ed lesson - we may
need to do some modification but it seems to look pretty good atm. 
*/
module fft_mag_sq #(
    parameter W = 16
)(
    input logic clk,
    input logic reset,
    input logic fft_valid,
    input logic signed [W-1:0] fft_real,
    input logic signed [W-1:0] fft_imag,

    output logic [2*W:0] mag_sq,
    output logic mag_valid,
    output logic add_stage
);

    logic signed [2*W-1:0] real_sq, imag_sq;
    logic [2*W:0] mag_pipeline;

    //square real and imagined
    always_ff @(posedge clk) begin
        if (reset) begin
            real_sq <= 0;
            imag_sq <= 0;
        end
        else if (fft_valid) begin
            real_sq <= signed'(fft_real) * signed'(fft_real);
            imag_sq <= signed'(fft_imag) * signed'(fft_imag);
        end
    end

    //add squares
    always_ff @(posedge clk) begin
        if (reset) begin
            add_stage <= 0;
        end
        else begin
            add_stage <= real_sq + imag_sq;
        end
    end

    //shift register for valid signal (2 cycle delay)
    logic [1:0] valid_shift;
    always_ff @(posedge clk) begin
        if (reset) begin
            valid_shift <= 2'b00;
        end
        else begin
            valid_shift <= {valid_shift[0], fft_valid};
        end
    end

  //altered this so it outputs on the clock cycle instead of continuously as we need to use this as a 
  //clocked input elsewhere - but can always go back to the continuous assign later
    logic [2*W:0] mag_sq_reg;
    always_ff @(posedge clk) begin
        if(reset) begin
            mag_sq_reg <= 0;
            mag_valid <= 0;
        end
        else begin
            mag_sq_reg <= add_stage;
            mag_valid <= valid_shift[1];
        end
    end

    assign mag_sq = mag_sq_reg; //just to make sure it changes on clock cycle
    /* ALTERED to be a clocked output for computing spec flux
    assign mag_sq = add_stage;
    assign mag_valid = valid_shift[1];
    */
endmodule
