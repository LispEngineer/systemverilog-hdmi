// Copyright 2022 Douglas P. Fields, Jr.

// See README.md for details.
// Generates a variety of HDMI video patterns based upon the
// the selected pattern input. Nothing particularly useful!

// Based upon Analog Devices AN-1270
// ADV7513-Based Video Generators
// Listing 2, Generated Video Patterns

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module pattern_vg #(
  parameter B=8, // number of bits per color channel
            X_BITS=13, // Bits in the X-size (displayable)
            Y_BITS=13, // Bits in the Y-size (displayable)
            FRACTIONAL_BITS=12 // For the ramp generator pattern
) (
  input  logic              clk,
  input  logic              reset, 
  
  // Inputs
  input  logic [X_BITS-1:0] x, // x/y coordinate (when dn_in) of what pixel we are currently on
  input  logic [Y_BITS-1:0] y,
  input  logic              vn_in, // vertical sync in
  input  logic              hn_in, // horizontal sync in
  input  logic              dn_in, // data enable in - when we're in a displayable pixel spot
  
  input  logic [X_BITS-1:0] max_x,   // # of columns of (visible) pixels
  input  logic [Y_BITS-1:0] max_y,   // # of rows of (visible) pixels
  input  logic [7:0]        pattern, // Which pattern to display?
  input  logic 
    [B+FRACTIONAL_BITS-1:0] ramp_step, // If it's a ramp, how much to ramp each column
                                       // to smoothly ramp up across max_x   

  // Pattern generator outputs
  output logic              vn_out, hn_out, den_out, // currently the same as the _in's
  output logic  [B-1:0]     r_out, g_out, b_out      // RGB channel pixel color output
);


logic [B+FRACTIONAL_BITS-1:0] ramp_values; // 12-bit fractional counter for ramp values

logic [12:0] color_count = 13'd666; // Random number that isn't all black

// Purpose: Output an RGB pixel value for every single
// x, y location when dn_in is true.
always @(posedge clk) begin
  // Not sure why we have these outputs the same as the inputs.
  // Maybe it gives us flexibility to have a delay in the pattern
  // generator (add a few clocks of latency or something).
  vn_out <= vn_in;
  hn_out <= hn_in;
  den_out <= dn_in;

  // Default outputs if we have nothing else to send
  r_out <= 8'h00;
  g_out <= 8'h00;
  b_out <= 8'h00;
  
  if (reset) begin
    ramp_values <= 0;
    color_count <= 13'd666;
    
  end else if (!dn_in) begin
    // We are not displaying data right now so...
    // Just leave the defaults.
    // INTENTIONALLY DOING NOTHING HERE
    
  end else if (pattern == 8'b0) begin
    // no pattern
    r_out <= 8'h80;
    g_out <= 8'h80;
    b_out <= 8'h80;
    
  end else if (pattern == 8'b1) begin
    // border
    if (x == 12'b0 || 
        y == 12'b0 || 
        x == max_x - 1 || 
        y == max_y - 1) begin
      r_out <= 8'hFF;
      g_out <= 8'hFF;
      b_out <= 8'hFF;
    end
    
  end else if (pattern == 8'd2) begin
    // moireX
    if (x[0] == 1'b1) begin
      r_out <= 8'hFF;
      g_out <= 8'hFF;
      b_out <= 8'hFF;
    end
    
  end else if (pattern == 8'd3) begin
    // moireY
    if (y[0] == 1'b1) begin
      r_out <= 8'hFF;
      g_out <= 8'hFF;
      b_out <= 8'hFF;
    end
    
  end else if (pattern == 8'd4) begin
    // Display a ramp using the top bits of the ramp_values, which
    // increments a bit every column.
    r_out <= ramp_values[B+FRACTIONAL_BITS-1:FRACTIONAL_BITS];
    g_out <= ramp_values[B+FRACTIONAL_BITS-1:FRACTIONAL_BITS];
    b_out <= ramp_values[B+FRACTIONAL_BITS-1:FRACTIONAL_BITS];
    if (x == max_x - 1)
      ramp_values <= 0;
    else if (x == 0)
      ramp_values <= ramp_step;
    else
      ramp_values <= ramp_values + ramp_step;
      
  end else if (pattern == 8'd5) begin
    // Doug's silly pattern #1 - dual ramps in R & G
    r_out <= x[7:0];
    g_out <= y[7:0];
    // And let's add in a B for fun
    b_out <= {x[9],y[8],6'b0};
    
  end else if (pattern == 8'd6) begin
    // An X-Y moire
    if (dn_in && (x[0] ^ y[0])) begin
      r_out <= 8'hFF;
      g_out <= 8'hFF;
      b_out <= 8'hFF;
    end

  end else if (pattern == 8'd7) begin
    // Make a pattern that shifts over time
    
    if (x == 0 && y == 0)
      color_count <= color_count + 1'b1;
      
    r_out <= color_count[9:2];
    g_out <= color_count[10:3];
    b_out <= 8'b0;
    
  end else if (pattern == 8'd8) begin
    // Make a diagonal line
    if (x == y) begin
      r_out <= 8'hFF;
      g_out <= 8'hFF;
      b_out <= 8'hFF;
    end
    
  end else begin
    // Default, if I haven't coded it yet
    r_out <= 8'hA0;
    g_out <= 8'h60;
    b_out <= 8'h00;
    
  end // pattern == ?
end // always

endmodule



`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// Restore the default_nettype to prevent side effects
// See: https://front-end-verification.blogspot.com/2010/10/implicit-net-declartions-in-verilog-and.html
// and: https://sutherland-hdl.com/papers/2006-SNUG-Boston_standard_gotchas_presentation.pdf
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif

