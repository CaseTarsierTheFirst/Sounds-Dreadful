//bpm snr version estimator

//NOT tested yet as has not been integrated into SNR. Just a draft - compiles in Quartus. 

//basic assumptions
//40-200BPM with +-10% error
/*
40bpm = 1500 beat intervals (ms) = 72,000 samples at 48kHz
200bpm = 300 beat intervals (ms) = 14,400 samples at 48kHz
10% error means we have to distinguish +-30ms (0.1 * 30) at 300 ms intervals, +-150ms at 1500ms intervals

At 48Khz --> sample = 1/48000 = 28.83 micro second
At 8 Khz --> sample = 1/8000 = 125 micro seconds (0.04% error for 300ms, 0.008% error 1500ms) - so is within 10% error easily
*/

module bpm_estimator #(
    parameter W = 16, //sample width of signal_rms
    //changed from 8000 to 48000 based on Peter's input - may need to change again
    parameter SAMPLE_FREQ = 48000, //apparently a suitable number if SNR is decimating from 48Khz. At 8kHz, time resolution is 125mico-sec, at 16kHz it is 62.5ms (better measurement) - have to just match it 
    //to postdecimation rate
    parameter signed [W-1:0] THRESHOLD = 16'sd500, //Need to tune signal amplitude units - is 500 in decimal
    parameter REFRAC_TIMER = 200, //ms - so we don't double count = 5 beats per second = 300bpm upper limit
    parameter WORD_LENGTH = 32, //bits for word for fixed-point rep
    parameter FRAC_LENGTH = 16 //bits for frac length in fixed-point rep
)(
    input logic clk,
    input logic reset,
    input logic signed [W-1:0] signal_rms, //signal-to-noise ratio moving average
    input logic sample_tick, //signal that new signal_rms valus has been received ever 125 micro-seconds from SNR
    
    output logic beat_pulse, //single cycle pulse for beat detected
    output logic [W-1:0] beat_strength, //integer for beat amp
    output logic [15:0] BPM_estimate //integer of current BPM estimate
);

    //detect signal_rms peak above a threshold and record them as onset/beat events
    
    //turn ms into clock cycles for refrac period
    localparam integer REFRAC_CYCLES = (SAMPLE_FREQ * REFRAC_TIMER) / 1000;
    logic [31:0] refractory_counter; //counts down refractory period
    logic refractory_active; //flag for if within refractory period

    logic [31:0] interval_counter; //counter for time between bteas
    logic [31:0] last_interval_counter_val; //stores last time between intervals from BPM calc
    
    //if we need bpm estimate output in fixed-point notation
    logic [WORD_LENGTH-1:0] bpm_fixed;
    logic [FRAC_LENGTH-1:0] bpm_int;
    logic [FRAC_LENGTH-1:0] bpm_frac;
    logic [WORD_LENGTH-1:0] numerator = 60 * SAMPLE_FREQ << 16;

    //logic for detecting beat above threshold
    always_ff @(posedge clk) begin
        if(reset) begin
            //reset outputs
            beat_pulse <= 0;
            beat_strength <= 0;
            BPM_estimate <= 0;

            //reset counters
            refractory_counter <= 0;
            refractory_active <= 0;
            interval_counter <= 0;
            last_interval_counter_val <= 0;
        end

        //defaults
        beat_pulse <= 0; //no beat

        //counter increment
      //if we don't want to count samples I can change this to counting how any 50Mhz ticks = 8Khz - but less synchronised
      if (sample_tick) begin //this ASSUMES peter is giving me 1 sample per sampling freq (8kHz) - so adjust sampleing freq if needed
           interval_counter <= interval_counter + 1;
       end

        //handle if within refractory period
        if (refractory_active) begin
            if (refractory_counter > 0) begin
                refractory_counter <= refractory_counter - 1;
            end
            else begin
                refractory_active <= 0;
            end
        end

        //beat detection threshold condition
        if (!refractory_active && signal_rms > THRESHOLD) begin
            //outputs
            beat_pulse <= 1;
            beat_strength <= signal_rms;
            bpm_fixed <= numerator / interval_counter; //if we need fixed point rep

            //store last value and reset interval counter
            last_interval_counter_val <= interval_counter;
            interval_counter <= 0;

            //reset refractory counter and put into active
            refractory_counter <= REFRAC_CYCLES;
            refractory_active <= 1;
        end

        //calculate BPM from inter-beat interval (time difference between consecutive beats)

        if (last_interval_counter_val != 0) begin
          //should possibly pipeline this operation
          //last_interval_counter_val / SAMPLE_FREQ = time between beats in seconds - inverse * 60 = bpm
            BPM_estimate <= (60 * SAMPLE_FREQ) / last_interval_counter_val;
            
            //if needing fixed point output:
            bpm_int <= bpm_fixed[WORD_LENGTH-1:FRAC_LENGTH]; //integer part
            bpm_frac <= bpm_fixed[FRAC_LENGTH-1:0]; //fraction part
        end

    end

endmodule
