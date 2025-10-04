/*This module compares the previous frame's magnitudes to the new frame's
magnitudes to see if there is a positive change. Positive changes of 1024
samples are summed = spectral flux for the frames

Currently, the summed spectral flux for 32 frames is stored in a buffer. This
is used to calculate a moving average of spectral flux sums to create a moving 
threshold. If the new spectral sum is larger than 2 * threshold, then a BEAT_VALID
signal is sent out alongside the outputted values. We can change this so that only
valid beats are sent out, but I think it's easier for the autocorrelation module just 
to check if it's valid --> if it is, it uses it, else it waits for the next sample. 

Based on Python Mini Lesson Beat Detection II - but verilog version
*/
module spectral_flux #(
    parameter N = 1024,     //Number of samples in each frames ("window")
    parameter W = 64,       //width of mag_sq is going to be double original word size. 
    parameter BIN_LENGTH = 10, // Counter binary length
    parameter MAX_FLUX_LENGTH = 70,
    parameter PREV_FRAMES_SPEC_FLUX = 32 // Tunable Value for the mean spectral flux
)(
    input logic clk,
    input logic reset,
    input logic mag_valid,  //valid signal from the magnitude module
    input logic [W-1:0] mag_sq,  //magnitude squared input - MAYBE NEED TO CHANGE TO SIGNED? 
    //input logic [BIN_LENGTH:0] bin_index, //0-1023 samples, 
    //input logic frame_done, //last bin of frame processed from magnitude module

    output logic [MAX_FLUX_LENGTH - 1:0] flux_value, //summed flux for current frame - worst case all have positive difference of 2^32, so 1024 * 2^ 32 = 4.39...x10^12 = 2^42
    output logic flux_valid, //valid signal one cycle after frame done

    //band mapped outputs - low, mid, high
    output logic [MAX_FLUX_LENGTH - 1:0] flux_low,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_mid,
    output logic [MAX_FLUX_LENGTH - 1:0] flux_high,
    output logic beat_valid,
	 
	 //debugging outputs
	 output logic frame_done,
	 output logic [MAX_FLUX_LENGTH - 1:0] flux_accum
);

	 //internal counter
	 logic [BIN_LENGTH - 1:0] counter;
	 //logic frame_done; //internal handshake signal
	 
	 logic frame_edge1, frame_edge2;
	 logic edge_detect_frame_done;
	 
	 always_ff @(posedge clk) begin
			frame_edge1 <= frame_done;
			frame_edge2 <= frame_edge1;
	 end
	 assign edge_detect_frame_done = (frame_edge1 && ! frame_edge2);
	 
    //previous mag, accumulating sum
    logic [W-1:0] prev_mag [0:N-1]; //array to store magnitudes of previous frames
    //logic [MAX_FLUX_LENGTH:0] flux_accum;      //variable to calculate the accumulated sum of each sample

    //difference calclation internal variables
    logic [W-1:0] prev_val;         //previous sample value
    logic signed [W-1:0] diff;             //difference temp variable
    logic [W-1:0] pos_diff;         //if difference is positive temp variable

    //band accumulators for band mapping
    logic [MAX_FLUX_LENGTH - 1:0] accum_low, accum_mid, accum_high;

    //Check if Valid Beat via average of spectral fluxes computed in prev. frames
    logic [MAX_FLUX_LENGTH - 1:0] flux_history [0:PREV_FRAMES_SPEC_FLUX-1];
    logic [$clog2(PREV_FRAMES_SPEC_FLUX)-1:0] flux_index;
    logic [MAX_FLUX_LENGTH - 1:0] flux_sum; //extra 5 just to make sure no overflow
    logic [MAX_FLUX_LENGTH - 1:0] flux_mean;
    logic [MAX_FLUX_LENGTH - 1:0] threshold;
	 
	
    always_ff @(posedge clk) begin
        if (reset) begin
            //reset all accumulators
            flux_accum <= 0;

            accum_low <= 0;
            accum_mid <= 0;
            accum_high <= 0;
				
				//reset counter
				counter <= 0;
				frame_done <= 0;
        end
		  
		  else if (edge_detect_frame_done) begin
				flux_accum <= 0;
				
				accum_low <= 0;
				accum_mid <= 0;
				accum_high <= 0;
		  end
		  
        else if (mag_valid) begin
				//counter logic
				if (counter == N-1) begin
					frame_done <= 1;
					counter <= 0;
				end
			   else begin
				   //counter logic
					counter <= counter + 1;
					frame_done <= 0;
		  
					prev_val <= prev_mag[counter];    //get previous value to match with current
					diff <= mag_sq - prev_val;        //compute the difference for the sample 
					pos_diff <= (diff[W-1] == 1'b0) ? diff : 0; //only record if MSB == 0 (positive)
					flux_accum <= flux_accum + pos_diff; //add to sum

					prev_mag[counter] <= mag_sq; //put current mag into old mag

						//splitting into bands for band mapping
						if (mag_sq <  256) begin
							 accum_low <= accum_low + pos_diff;
						end
						else if (mag_sq < 1024) begin
							 accum_mid <= accum_mid + pos_diff;
						end
						else begin
							 accum_high <= accum_high + pos_diff;
						end
				 end
         end
		
    end

	 logic [4:0] counter_valid;
	 
    always_ff @(posedge clk) begin
        if (reset) begin
            flux_value <= 0;
            flux_valid <= 0;

            //band mapped
            flux_low <= 0;
            flux_mid <= 0;
            flux_high <= 0;
				
				counter_valid <= 0;
        end
        else if (edge_detect_frame_done) begin
				
            flux_value <= flux_accum; //send out accumulated value for last frame
            flux_valid <= 1; //send out valid signal to autocorrelation module
            //flux_accum <= 0; //reset for next frame
				
				counter_valid <= 20 ;

            //band mapped
            flux_low <= accum_low;
            flux_high <= accum_high;
            flux_mid <= accum_mid;

            //Calculate mean of frame for thresholding
            flux_sum <= flux_sum - flux_history[flux_index] + flux_accum; //remove oldest value and add newest value
            flux_history[flux_index] <= flux_accum;
            flux_index <= (flux_index == PREV_FRAMES_SPEC_FLUX - 1) ? 0 : flux_index + 1;

            flux_mean <= flux_sum / PREV_FRAMES_SPEC_FLUX; //compute new mean
            threshold <= flux_mean << 1; //threshold is 2*mean for sample

            beat_valid <= (flux_accum > threshold) ? 1 : 0; //valid if sum is larger than threshold
        end
		  else begin
			counter_valid <= counter_valid - 1;
			if (counter_valid == 0) begin
				flux_valid <= 0;
				beat_valid <= 0;
			end
		  end
 //       else begin
//				counter <= counter + 1;
//            flux_valid <= 0;
//            beat_valid <= 0;
 //       end
    end
	 
	 
endmodule