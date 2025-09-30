// sevenseg_display8.sv
// 8-digit 7-seg: [HEX7..HEX0] = [S][R][SNR tens][SNR ones][BPM thou][BPM hund][BPM tens][BPM ones]
module sevenseg_display8 #(
  parameter bit ACTIVE_LOW = 1,          // 1 = active-low segments (DE2-115)
  parameter bit BLANK_LEADING_ZEROS = 1  // 1 = blank leading zeros in the 4-digit value
)(
  // PACKING EXPECTED:
  //   value[7:0]   = SNR (0..99)      -> shows on HEX5..HEX4
  //   value[15:4]  = BPM (0..4095)    -> shows on HEX3..HEX0
  input  logic [15:0] value,
  output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);

  // Digit to segments (a..g). Active-low patterns here; invert later if needed.
  function automatic logic [6:0] seg_digit(input logic [3:0] d);
    case (d)
      4'd0: seg_digit = 7'b100_0000;
      4'd1: seg_digit = 7'b111_1001;
      4'd2: seg_digit = 7'b010_0100;
      4'd3: seg_digit = 7'b011_0000;
      4'd4: seg_digit = 7'b001_1001;
      4'd5: seg_digit = 7'b001_0010;
      4'd6: seg_digit = 7'b000_0010;
      4'd7: seg_digit = 7'b111_1000;
      4'd8: seg_digit = 7'b000_0000;
      4'd9: seg_digit = 7'b001_0000;
      default: seg_digit = 7'b111_1111; // blank
    endcase
  endfunction

  // Limited letters
  localparam logic [6:0] SEG_S    = 7'b001_0010; // 'S' (approx using 7-seg)
  localparam logic [6:0] SEG_R    = 7'b010_1111; // 'r' (lowercase-ish); change if you prefer 'R'
  localparam logic [6:0] SEG_BLNK = 7'b111_1111; // blank

  function automatic logic [6:0] pol(input logic [6:0] raw);
    pol = (ACTIVE_LOW) ? raw : ~raw;
  endfunction

  // -------- Unpack fields (Quartus-friendly: no init-in-decl) --------
  logic [7:0]  snr_raw;
  logic [7:0]  snr_disp;
  logic [11:0] bpm_raw12;
  logic [15:0] bpm_disp;

  assign snr_raw   = value[7:0];
  assign snr_disp  = (snr_raw > 8'd99) ? 8'd99 : snr_raw;

  assign bpm_raw12 = value[15:4];          // 12-bit field from top level
  assign bpm_disp  = {4'd0, bpm_raw12};    // 0..4095 (well below 9999)

  // -------- SNR 2 digits --------
  logic [3:0] snr_tens, snr_ones;
  always_comb begin
    snr_tens = (snr_disp / 10) % 10;
    snr_ones = (snr_disp     ) % 10;
  end

  // -------- BPM 4 digits --------
  logic [3:0] bpm_thou, bpm_hund, bpm_tens, bpm_ones;
  always_comb begin
    bpm_thou = (bpm_disp / 1000) % 10;
    bpm_hund = (bpm_disp /  100) % 10;
    bpm_tens = (bpm_disp /   10) % 10;
    bpm_ones = (bpm_disp       ) % 10;
  end

  // Optional blanking of leading zeros on the 4-digit BPM field
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

  // Assign to physical digits (left→right: HEX7..HEX0)
  // [S][R][SNR tens][SNR ones][BPM thou][BPM hund][BPM tens][BPM ones]
  assign HEX7 = pol(SEG_S);
  assign HEX6 = pol(SEG_R);
  assign HEX5 = pol(seg_digit(snr_tens));
  assign HEX4 = pol(seg_digit(snr_ones));
  assign HEX3 = pol(seg_bpm_thou);
  assign HEX2 = pol(seg_bpm_hund);
  assign HEX1 = pol(seg_bpm_tens);
  assign HEX0 = pol(seg_bpm_ones);

endmodule
