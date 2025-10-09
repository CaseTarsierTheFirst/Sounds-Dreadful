// === CDC fixes (pixel clock domain = clk) ===

// 1) sync the 1-bit switch
logic switch_s1, switch_s2;
always_ff @(posedge clk) begin
  switch_s1 <= switch;
  switch_s2 <= switch_s1;
end
wire switch_safe = switch_s2;

// 2) latch BPM once per frame (avoid torn multi-bit reads)
logic [15:0] bpm_frame = 16'd0;
always_ff @(posedge clk) begin
  // latch at start of a valid frame
  if (startofpacket && valid) begin
    bpm_frame <= final_bpm_estimate;  // sampled atomically for the whole frame
  end
end


// threshold (make it explicitly 16 bits)
logic [15:0] BPM_threshold = 16'd0;

// filter select from the synced switch
logic [3:0] filter_select;
always_comb begin
  filter_select = switch_safe ? 4'b0001 : 4'b0010; // invert vs lighten
end


always_comb begin
  // defaults
  r_filt = r4; g_filt = g4; b_filt = b4;

  if (bpm_frame > BPM_threshold) begin
    case (filter_select)
      4'b0001: begin // invert
        r_filt = ~r4; g_filt = ~g4; b_filt = ~b4;
      end
      4'b0010: begin // lighten
        r_filt = r4 + ((15 - r4) >> 2) + ((15 - r4) >> 3);
        g_filt = g4 + ((15 - g4) >> 2) + ((15 - g4) >> 3);
        b_filt = b4 + ((15 - b4) >> 2) + ((15 - b4) >> 3);
        if (r_filt > 15) r_filt = 15;
        if (g_filt > 15) g_filt = 15;
        if (b_filt > 15) b_filt = 15;
      end
      // ... other cases ...
      default: ; // leave defaults
    endcase
  end
end
