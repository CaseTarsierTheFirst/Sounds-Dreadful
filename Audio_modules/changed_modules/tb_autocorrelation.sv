//autcorrelation testbench

`timescale 1ns/1ns

module tb_autocorrelation;

	//Parameters
	localparam W = 16; //lower for sim
	localparam N = 8; //lower for sim
	localparam CLK_PERIOD = 20;
	
	//DUT I/O
	logic clk;
	logic reset;
	logic flux_valid;
	logic beat_valid;
	logic [W-1:0] flux_in;
	
	logic [W-1:0] BPM_estimate;
	logic bpm_valid;
	
	//DUT instantiation
	autcorrelation #(.W(W), .N(N)) dut (
		.clk(clk),
		.reset(reset),
		.flux_valid(flux_valid),
		.flux_in(flux_in),
		.beat_valid(beat_valid),
		.BPM_estimate(BPM_estimate),
		.bpm_valid(bpm_valid),
		.state_out()
	);
	
	//Clock Generation
	initial clk = 0;
	always #(CLK_PERIOD/2) clk = ~clk;
	
	//Testbench
	initial begin
		reset = 1;
		flux_valid = 0;
		beat_valid = 0;
		flux_in = 0;
		
		#(CLK_PERIOD * 5);
		reset = 0;
		
		//Simulate a periodic beat
		repeat (50) begin
			@(posedge clk);
			flux_in = 100 + $urandom_range(0,50);
			flux_valid = 1;
			beat_valid = (flux_in > 120); //simple threshold for sim purpose
			
			//next clock edge
			@(posedge clk)
			flux_valid = 0; //1 cycle pulse
			beat_valid = 0; //1 cycle pulse
		end
		#(CLK_PERIOD*200);
		$stop;
	end
	
	//Outputs for Transcript in ModelSim
	initial begin
        $display("Time\tFlux\tBeat\tBPM\tBPM_valid");
        $monitor("%0t\t%0d\t%b\t%0d\t%b", 
                 $time, flux_in, beat_valid, BPM_estimate, bpm_valid);
    end
	
endmodule
	
	
	
