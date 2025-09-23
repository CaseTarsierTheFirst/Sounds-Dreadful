`timescale 1ps/1ps
module mic_load #(parameter N=16) (
	input bclk, // Assume a 18.432 MHz clock
    input adclrc,
	input adcdat,
    // No ready signal nor handshake: as this module streams live audio data, it cannot be stalled, therefore we only have the valid signal.
    output logic valid,
    output logic [N-1:0] sample_data
);
    // Assume that i2c has already configured the CODEC for LJ data, MSB-first and N-bit samples.

    // Rising edge detect on ADCLRC to sense left channel
    logic redge_adclrc, adclrc_q; 
    always_ff @(posedge  bclk) begin : adclrc_rising_edge_ff
        adclrc_q <= adclrc;
    end
    assign redge_adclrc = ~adclrc_q & adclrc; // rising edge detected!

    logic [4:0] bit_index = 5'd16;
    logic [N-1:0] temp_rx_data;

    always_ff @(posedge bclk) begin
        valid <= 1'b0;  

        if (redge_adclrc) begin
            temp_rx_data[N-1] <= adcdat;
            bit_index <= 5'd1;
        end
        else if (bit_index < N) begin
            
            if (bit_index == N-1) begin
                
                temp_rx_data[0] <= adcdat;                         
                sample_data <= {temp_rx_data[N-1:1], adcdat};  
                valid <= 1'b1;
                bit_index <= 5'd16;               
            end else begin
                temp_rx_data[(N-1)-bit_index] <= adcdat;           
                bit_index <= bit_index + 1'b1;
            end
        end

    end




    /*
     * Implement the Timing diagram.
     * -----------------------------
     * You should use a temporary N-bit RX register to store the ADCDAT bitstream from MSB to LSB.
     * Remember that MSB is first, LSB is last.
     * Use `temp_rx_data[(N-1)-bit_index] <= adcdat;`
     * BCLK rising is your trigger to sample the value of ADCDAT into the register at the appropriate bit index.
     * ADCLRC rising (see `redge_adclrc`) signals that the MSB should be sampled on the next rising edge of BCLK.
     * With the above, think about when and how you would reset your bit_index counter.
     */

endmodule

