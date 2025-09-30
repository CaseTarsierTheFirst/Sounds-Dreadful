// sevenseg_snr_bpm.sv
// 8-digit 7-seg: [HEX7..HEX0] = [S][R][SNR tens][SNR ones][BPM thou][BPM hund][BPM tens][BPM ones]
module sevenseg_snr_bpm #(
  parameter bit ACTIVE_LOW = 1,
  parameter bit BLANK_LEADING_ZEROS = 1
)(
  input  logic [7:0]  snr_val,     // 0..99 will be shown; clamped
  input  logic [15:0] bpm_val,     // 0..9999 will be shown; blanks leading zeros if enabled
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);

  // digit encoder (active-low patterns; invert at end if needed)
  function automatic logic [6:0] seg_digit(input logic [3:0] d);
    case (d)
      4'd0: seg_digit = 7'b1000000; 4'd1: seg_digit = 7'b1111001;
      4'd2: seg_digit = 7'b0100100; 4'd3: seg_digit = 7'b0110000;
      4'd4: seg_digit = 7'b0011001; 4'd5: seg_digit = 7'b0010010;
      4'd6: seg_digit = 7'b0000010; 4'd7: seg_digit = 7'b1111000;
      4'd8: seg_digit = 7'b0000000; 4'd9: seg_digit = 7'b0010000;
      default: seg_digit = 7'b1111111;
    endcase
  endfunction

  localparam logic [6:0] SEG_S    = 7'b0010010; // looks like 'S'
  localparam logic [6:0] SEG_R    = 7'b0101111; // crude 'r'
  localparam logic [6:0] SEG_BLNK = 7'b1111111;

  function automatic logic [6:0] pol(input logic [6:0] raw);
    pol = (ACTIVE_LOW) ? raw : ~raw;
  endfunction

  // clamp SNR to 0..99
  logic [7:0] snr_disp;
  assign snr_disp = (snr_val > 8'd99) ? 8'd99 : snr_val;

  // split SNR two digits
  logic [3:0] snr_tens, snr_ones;
  always_comb begin
    snr_tens = (snr_disp / 10) % 10;
    snr_ones =  snr_disp % 10;
  end

  // clamp BPM to 0..9999 and split four digits
  logic [15:0] bpm_clamped;
  assign bpm_clamped = (bpm_val > 16'd9999) ? 16'd9999 : bpm_val;

  logic [3:0] bpm_thou, bpm_hund, bpm_tens, bpm_ones;
  always_comb begin
    bpm_thou = (bpm_clamped / 1000) % 10;
    bpm_hund = (bpm_clamped /  100) % 10;
    bpm_tens = (bpm_clamped /   10) % 10;
    bpm_ones =  bpm_clamped % 10;
  end

  // optional blanking
  logic [6:0] seg_bpm_thou, seg_bpm_hund, seg_bpm_tens, seg_bpm_ones;
  always_comb begin
    seg_bpm_thou = seg_digit(bpm_thou);
    seg_bpm_hund = seg_digit(bpm_hund);
    seg_bpm_tens = seg_digit(bpm_tens);
    seg_bpm_ones = seg_digit(bpm_ones);
    if (BLANK_LEADING_ZEROS) begin
      if (bpm_thou == 0) begin
        seg_bpm_thou = SEG_BLNK;
        if (bpm_hund == 0) begin
          seg_bpm_hund = SEG_BLNK;
          if (bpm_tens == 0) begin
            seg_bpm_tens = SEG_BLNK;
          end
        end
      end
    end
  end

  // drive the displays
  assign HEX7 = pol(SEG_S);
  assign HEX6 = pol(SEG_R);
  assign HEX5 = pol(seg_digit(snr_tens));
  assign HEX4 = pol(seg_digit(snr_ones));
  assign HEX3 = pol(seg_bpm_thou);
  assign HEX2 = pol(seg_bpm_hund);
  assign HEX1 = pol(seg_bpm_tens);
  assign HEX0 = pol(seg_bpm_ones);

endmodule
