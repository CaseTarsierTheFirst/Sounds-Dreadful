/*
Based off my understanding of Ed MiniLesson Beat Detection II in Python - Autocorrelation Section
Autocorrelation = shifting signal and then comparing similarities with original
- Detects beat when shift value matches up with BPM
- Formula: Autocorrelation (t) = sum of signal value at time i + signal value at time i + t from 0-N (N = signal length)

Basically we convert BPM range to lags, then add in the frequency
bin we want to analyse (low, mid, or high - so we instantiate three of these and calculate autocorrelation for each).
Then, 
*/

module autocorrelation #(
    parameter N = 64, //can use a smaller number for less latency?
    parameter W = 32,
    parameter MIN_BPM = 40,
    parameter MAX_BPM = 200,
    parameter LOWER_LAG = 2400, //for max bpm of 200 (lower lag = 60/max_bpm * sample_rate)
    parameter UPPER_LAG = 12000, //for min bpm of 40, sample rate 8000
    parameter LAG_RANGE = UPPER_LAG - LOWER_LAG + 1,
    parameter SAMPLE_RATE = 8000, //may need to change this
    parameter FRAME_SIZE = 32 //number of historical frames we use
)(
    input logic clk,
    input logic reset,
    input logic flux_valid,
    input logic [W-1:0] flux_in, //can be low, mid, high band
    input logic beat_valid, //if spectral flux sum met threshold condition

    output logic [15:0] BPM_estimate,
    output logic bpm_valid
);

    logic [W-1:0] flux_history [0:N-1];
    logic [W+10:0] autocorr[0:LAG_RANGE-1];

    integer i;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < N; i = i + 1) begin 
                flux_history[i] <= 0;
            end
        end
        else if (flux_valid && beat_valid) begin
            for (i = N-1; i > 0; i = i - 1) begin //for each flux pos_diff value
                flux_history[i] <= flux_history[i-1]; //shift values down
            flux_history[0] <= flux_in; //add in new flux value
            end
        end
    end

    //autocorrelation over range of lags
    logic [W+10:0] autocorr [LOWER_LAG:UPPER_LAG];
    logic [7:0] best_lag;
    logic [W+10:0] best_score;

    always_ff @(posedge clk) begin
        if (reset) begin
            best_lag <= 0;
            best_score <= 0;
            bpm_valid <= 0;
        end
        else if (flux_valid && beat_valid) begin //output from spectral flux is valid
            best_score <= 0;
            best_lag <= LOWER_LAG;
            //go through lag range
            for (int i = LOWER_LAG; i <= UPPER_LAG; i = i + 1) begin
                autocorr[i-LOWER_LAG] <= 0; //reset for each lag value
                //for each stored valid flux value
                for (int j = 0; j < N - i; j = j + 1) begin
                    //compute new autocorrelation - sum of spectral flux and spectral shift i frames later - peak is where it matches
                    if (j + i < N) begin
                        autocorr[i-LOWER_LAG] = autocorr[i-LOWER_LAG] + flux_history[j] * flux_history[j+i];
                    end
                    
                    if (autocorr[i-LOWER_LAG] > best_score) begin
                        best_score <= autocorr[i-LOWER_LAG];
                        best_lag <= i;
                    end
                end
            end
            bpm_valid <= 1;
        end
        else begin
            bpm_valid <= 0;
        end
    end

    //bpm conversion
    always_ff @(posedge clk) begin
        if (reset) begin
            BPM_estimate <= 0;
        end
        else if (bpm_valid) begin
            BPM_estimate <= (60 * SAMPLE_RATE) / best_lag;
        end
    end
endmodule
