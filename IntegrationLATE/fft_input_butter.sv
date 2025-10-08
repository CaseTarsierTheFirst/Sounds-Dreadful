module fft_input_buffer #(
    parameter W = 16,
    parameter NSamples = 1024
) (
     input                clk,
     input                reset,
     input                audio_clk,
     
     input  logic         audio_input_valid,
     output logic         audio_input_ready,
     input  logic [W:0]   audio_input_data,

     output logic [W-1:0] fft_input,
     output logic         fft_input_valid
);
    logic fft_read;
    logic full, wr_full;

    // Instantiatied Variables for samples and count
    localparam int CNTW = $clog2(NSamples);
    logic [CNTW:0] cnt;
	 logic [CNTW:0] cnt2;
    logic flushing;
    logic full_rd_q;


    fifo u_fifo (.aclr(reset),
                        .data(audio_input_data[W-1:0]),.wrclk(audio_clk),.wrreq(audio_input_valid),.wrfull(wr_full),
                        .q(fft_input),          .rdclk(clk),      .rdreq(fft_read),         .rdfull(full)    );
    assign audio_input_ready = !wr_full;

    assign fft_input_valid = fft_read; // The Async FIFO is set such that valid data is read out whenever the rdreq flag is high.
	 
	 logic audio_clk_sync0, audio_clk_sync1;
	 logic audio_ckl_rising;
	 
	 //edge detect audio clock
	 always_ff @ (posedge audio_clk) begin
		audio_clk_sync0 <= audio_clk;
		audio_clk_sync1 <= audio_clk_sync0;
	 end
	 
	 assign audio_clk_rising = (audio_clk_sync0 && ! audio_clk_sync1);
	 
	 always_ff @(posedge audio_clk) begin
			cnt2 <= cnt2 + 1;
		if (cnt2 >= NSamples -1) begin
			cnt2 <= 0;
		end
	 end
    
    //TODO implement a counter n to set fft_read to 1 when the FIFO becomes full (use full, not wr_full).
    // Then, keep fft_read set to 1 until 1024 (NSamples) samples in total have been read out from the FIFO.
    assign fft_read = flushing;/* Fill-in */
    always_ff @(posedge clk) begin : fifo_flush
        if (reset) begin
            flushing <= 1'b0;
            cnt <= 0;
            full_rd_q <= 1'b0;
        end
        else begin
            full_rd_q <= full;

            if (!flushing) begin
				/*
                if(full && full_rd_q) begin
                    flushing <= 1'b0;
                    cnt <= 0;
                end
                else begin
                    cnt <= 0;
                end */
					 if (cnt2 >= NSamples - 1) begin
						  flushing <= 1;
						  //cnt2 <= 0;
						  cnt <= 0;
					 end
            end
            else begin
                if (cnt == NSamples-1) begin
                    flushing <= 1'b0;
                    cnt <= 0;
                end 
                else begin
                    cnt <= cnt + 1;                     
                end
            end
        end
        // Increment your counter here.
        // Remember to use reset.
    end
endmodule
