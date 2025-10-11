//Testbench - hanning window

`timescale 1ns/1ns
module tb_hanning_window;

	//Parameters
	localparam W = 16;
	localparam N = 1024; //Needs to match file
	localparam CLK_PERIOD = 20;
	
	//DUT I/O
	logic clk;
	logic reset;
	logic sample_in_valid;
	logic sample_in_ready;
	logic [W-1:0] sample_in;
	
	logic [(2*W-1):0] windowed_sample;
	logic windowed_valid;
	logic frame_done;
	
	//DUT Instantiation
	hanning_window #(.W(W), .N(N)) dut (
		.clk(clk),
		.reset(reset),
		.sample_in_valid(sample_in_valid),
		.sample_in_ready(sample_in_ready),
		.sample_in(sample_in),
		.windowed_sample(windowed_sample),
		.windowed_valid(windowed_valid),
		.frame_done(frame_done)
	);
	
	//Clock Generation
	initial clk = 0;
	always #(CLK_PERIOD/2) clk = ~clk;
	
	//Input Data Generation
	real t = 0.0;
	real fs = 1.0/CLK_PERIOD;
	real freq = 1.0 / N; //1 cycle per N samples
	int n = 0;
	
	always @(posedge clk) begin
		if (!reset) begin
			//sample_in = $rtoi($sin(2.0 * 3.141592653 * freq * n) * ((1 << (W-1))-1));
			sample_in = n;
			sample_in_valid = 1;
			n = n + 1;
			if (n == N) begin
				n = 0;
			end
		end
		else begin
			sample_in_valid = 0;
			sample_in = 0;
		end
	end
	
	//handshake display check
	always @(posedge clk) begin
		if (windowed_valid) begin
			$display("Sample %0d: input=%0d, windowed=%0d", dut.sample_index, sample_in, windowed_sample);
		end
		if (frame_done) begin
			$display("Frame Completed!");
		end
	end
	
	//simulation control
	initial begin
		reset = 1;
		#100 reset = 0;
		#1000000 $stop;
	end
	
endmodule
	
