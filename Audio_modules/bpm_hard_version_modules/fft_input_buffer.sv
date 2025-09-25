/*
This module is a FIFO buffer that takes in the decimated stream from 
the frontend audio module in preparation to read it into the Hanning window.
The frame_ready signal goes high when the FIFO is full and data can start being sampled
into the Hanning window module
*/
module fft_input_buffer #(
    parameter W = 16,
    parameter NSamples = 1024
) (
     input                clk,
     input                reset,
     input                audio_clk,
     
     input  logic         audio_input_valid,
     output logic         audio_input_ready,
     input  logic [W:0]   audio_input_data, //should maybe be W-1?

     output logic [W:0] fft_input, //modified to W, was W-1
     output logic         fft_input_valid,
     output logic         frame_ready //signals full frame is available for hanning module
);
    logic fft_read;
    logic full, wr_full;

    async_fifo u_fifo (.aclr(reset),
                        .data(audio_input_data),.wrclk(audio_clk),.wrreq(audio_input_valid),.wrfull(wr_full),
                        .q(fft_input),          .rdclk(clk),      .rdreq(fft_read),         .rdfull(full)    );
    
    assign audio_input_ready = !wr_full;
    assign fft_input_valid = fft_read; // The Async FIFO is set such that valid data is read out whenever the rdreq flag is high.
    
    //implement a counter n to set fft_read to 1 when the FIFO becomes full (use full, not wr_full).
    logic [10:0] counter; //2^10 = 1024
    logic counter_flag;

    // Then, keep fft_read set to 1 until 1024 (NSamples) samples in total have been read out from the FIFO.
    assign fft_read = counter_flag; 
    assign frame_ready = (counter == NSamples); //signals when full frame is read
    
    always_ff @(posedge clk) begin : fifo_flush
        if (reset) begin
            counter <= 0;
            counter_flag <= 0;
        end
        else begin
            if (!counter_flag) begin
                if (full) begin
                    counter_flag <= 1;
                    counter <= 1;
                end
            end
            else begin
                counter <= counter + 1;
                if (counter == NSamples) begin
                    counter <= 0;
                    counter_flag <= 0;
                end
            end
        end
    end
endmodule
