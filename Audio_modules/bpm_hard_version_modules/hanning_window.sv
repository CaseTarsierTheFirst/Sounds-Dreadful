/*this module is meant to go AFTER the FIFO samples pass through a low-pass filter and then need to be windowed. 
We need to get the actual hanning coefficients in from a python code somewhere that I haven't done yet, but will do soon. 
Essentially we go sample by sample nad apply the corresponding hanning coefficient to the sample. 
*/
module hanning_window #(
    parameter W = 16,
    parameter N = 1024; //sample size
    parameter MAX_SAMPLE_INDEX = 9
)(
    input logic clk,
    input logic reset,
	 input logic fft_input_valid, //valid signal from FIFO
	 output logic sample_in_ready, //tell FIFO it can accept
    input  logic sample_in_valid,
	 input logic [W-1:0] sample_in,
    input logic [MAX_SAMPLE_INDEX:0] sample_index, //from 0 to 1023

  output logic [(W-1):0] windowed_sample, //going to be 2x the length due to product
  output logic windowed_valid
);

    logic [W-1:0] hanning_coeff [0:N-1]; //has to be reversed
    logic [2*W-1:0] product;
	 logic [W-1:0] rounded;
	 
    //read in hanning coefficients from python
    initial begin
        $readmemh("hanning_coeff.mem", hanning_coeff);
    end
	 
	 //assume hanning can accept one sample per cycle right now
	 assign sample_in_ready = 1'b1;
	 
	 always_comb begin
			product = sample_in * hanning_coeff[sample_index];
	 end
	 
	 always_comb begin
			rounded = product[2*W-1 -: W]; //top W bits
	 end

    //register output + valid with one cycle latency
    always_ff @ (posedge clk) begin
        if (reset) begin
            windowed_sample <= 0;
				windowed_valid <= 0;
        end
        else begin
				if (sample_in_valid && sample_in_ready) begin
					windowed_sample <= rounded;
					windowed_valid <= 1'b1;
				end
				else begin
					windowed_valid <= 1'b0;
				end
        end
    end
	 
endmodule
