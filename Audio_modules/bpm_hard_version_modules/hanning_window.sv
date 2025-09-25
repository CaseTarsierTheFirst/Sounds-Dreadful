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
    input logic [W-1:0] sample_in,
    input logic [MAX_SAMPLE_INDEX:0] sample_index, //from 0 to 1023

  output logic [(2*W-1):0] windowed_sample //going to be 2x the length due to product
);

    logic [W-1:0] hanning_coeff [0:N-1]; //has to be reversed
    
    //read in hanning coefficients from python
    initial begin
        $readmemh("hanning_coeff.mem", hanning_coeff);
    end

    //window the sample
    always_ff @ (posedge clk) begin
        if (reset) begin
            windowed_sample <= 0;
        end
        else begin
            windowed_sample <= sample_in * hanning_coeff[sample_index];
        end
    end
endmodule

