// Copyright 2022_Douglas P. Fields, Jr. All Rights Reserved.

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif

// Set up the ADV7513 HDMI processor via I2C.
// ROM code is per AN-1270.

// See: https://verilogguide.readthedocs.io/en/latest/verilog/designs.html#read-only-memory-rom


module setup_rom (
  input  logic [7:0]  address,
  output logic [23:0] data,
  output logic [7:0]  rom_length
);

assign rom_length = 8'd25;

// TODO: We could get rid of the address if we wanted

always_comb
  case (address)
    8'd0: data = 24'h72_01_00; // Set N Value(6144)
    8'd1: data = 24'h72_02_18; // Set N Value(6144)
    8'd2: data = 24'h72_03_00; // Set N Value(6144)
    8'd3: data = 24'h72_15_00; // Input 444 (RGB or YCrCb) with Separate Syncs
    8'd4: data = 24'h72_16_61; // 44.1kHz fs, YPrPb 444
    8'd5: data = 24'h72_18_46; // CSC disabled
    8'd6: data = 24'h72_40_80; // General Control Packet Enable
    8'd7: data = 24'h72_41_10; // Power Down control
    8'd8: data = 24'h72_48_48; // Reverse bus, Data right justified
    8'd9: data = 24'h72_48_A8; // Set Dither_mode - 12-to-10 bit
    8'd10: data = 24'h72_4C_06; // 12_bit Output
    8'd11: data = 24'h72_55_00; // Set RGB444 in AVinfo Frame
    8'd12: data = 24'h72_55_08; // Set active format Aspect
    8'd13: data = 24'h72_96_20; // HPD Interrupt clear
    8'd14: data = 24'h72_98_03; // ADI required Write
    8'd15: data = 24'h72_98_02; // ADI required Write
    8'd16: data = 24'h72_9C_30; // ADI required Write
    8'd17: data = 24'h72_9D_61; // Set clock divide
    8'd18: data = 24'h72_A2_A4; // ADI required Write
    8'd19: data = 24'h72_43_A4; // ADI required Write
    8'd20: data = 24'h72_AF_16; // Set HDMI Mode
    8'd21: data = 24'h72_BA_60; // No clock delay
    8'd22: data = 24'h72_DE_9C; // ADI required write
    8'd23: data = 24'h72_E4_60; // ADI required Write
    8'd24: data = 24'h72_FA_7D; // Nbr of times to search for good phase
    default: data = 24'h0;
  endcase

endmodule // setup_rom


module adv7513_setup #(
  parameter CNT_200MS = 32'd10_000_000 // clock cycles to 200ms; Default to 10M cycles at 50MHz
) (
  input logic clk,
  input logic rst,
  
  // Interface with the I2C controller
  output logic       i2c_activate,
  input  logic       i2c_busy,
  output logic [6:0] i2c_address,
  output logic       i2c_readnotwrite,
  output logic [7:0] i2c_byte1,
  output logic [7:0] i2c_byte2,
  
  // Setup outputs
  output logic active,
  output logic done,
  
  // Debugging outputs
  output logic is_busywait,
  output logic is_busyseen
);

initial active = 0;
initial done = 0;

// This is a state machine that runs once, after 200ms,
// setting up the ADV7513 per the ROM above.

localparam S_RESET    = 3'd0, // Reset all our setup params, goes to WAIT
           S_WAIT     = 3'd1, // Wait 200ms for the ADV7513 to power up, continues to BUSYWAIT
           S_SEND     = 3'd2, // Send a byte of the ROM to the ADV7513, goes to BUSYWAIT or DONE
           S_BUSYWAIT = 3'd3, // Wait for the I2C controller to be done sending, always returns to SEND after incrementing the rom_step
           S_DONE     = 3'd4; // Finished all the sending; terminal state

logic [2:0]  setup_state = S_RESET;
logic [7:0]  rom_step;
logic [7:0]  rom_length;
logic [23:0] cnt_wait;
logic [23:0] rom_comb; // Combinatoric output. I2C address (with read/write bit set to write), then two (write) data fields

logic busy_seen; // Have we seen the I2C controller go busy?

// The ROM is implemented combinatorically
setup_rom setup_rom(
  .address(rom_step),
  .data(rom_comb),
  .rom_length
);

// Debug outputs
assign is_busyseen = busy_seen;
assign is_busywait = setup_state == S_BUSYWAIT;

always_ff @(posedge clk) begin

  if (rst) begin
    setup_state <= S_RESET;
    active <= 0;
    done <= 0;
  
  end else case (setup_state)
  
    S_RESET: begin
      // Start our whole state machine over
      rom_step <= 0;
      cnt_wait <= 0;
      setup_state <= S_WAIT;
      i2c_activate <= 0;
      busy_seen <= 0;
      active <= 1;
      done <= 0;
    end // S_RESET
    
    S_WAIT: begin
      // Wait 200ms before we try to initialize our ADV7513 per 
      // Section 6.6.1 of ADV7513 Hardware User's Guide
      if (cnt_wait == CNT_200MS) begin
        setup_state <= S_BUSYWAIT; // Always check if I2C is busy before starting
        busy_seen <= 1; // But pretend it was already busy, else it will wait to see it busy first
        rom_step <= 0;
        cnt_wait <= 0;
      end else begin
        cnt_wait <= cnt_wait + 24'd1;
        i2c_activate <= 0;
        busy_seen <= 0;
      end
    end // S_WAIT
    
    S_SEND: begin
      // Send the next command from our ROM to the ADV7513 via I2C
      if (rom_step == rom_length)
        // We have run out of commands and are done with setup!
        setup_state <= S_DONE;
        
      else begin
        // Always reset for our next busy wait
        busy_seen <= 0;
        setup_state <= S_BUSYWAIT;
        
        // Activate our I2C controller (next cycle, of course)
        // and then wait for it to finish this command.
        i2c_activate <= 1;
        {i2c_address, i2c_readnotwrite, i2c_byte1, i2c_byte2} <= rom_comb;
        
      end // Not done
    end // S_SEND
    
    S_BUSYWAIT: begin
      // Wait until we see the I2C start and then stop being busy.
      // Remember that we are running at full clock speed
      // compared to the 128x slower 400 kHz I2C bus
      // (assuming we're running at 50MHz).
      
      if (!busy_seen) begin
        // Do nothing, wait to see I2C controller go busy
        if (i2c_busy) begin
          // Okay we saw the busy go on, we can deactivate
          busy_seen <= 1;
          i2c_activate <= 0;
          // And move on to the next step
          rom_step <= rom_step + 8'd1;
        end
        
      end else if (!i2c_busy) begin
        // We saw it go from busy to non-busy, so we're done waiting
        busy_seen <= 0;
        i2c_activate <= 0; // Just in case?
        // rom step was already advanced
        setup_state <= S_SEND;
      end
      
      // TODO: Make it so it stops busy waiting after a reasonable number of I2C cycles.
      // If we see that happen, go to reset state.
      // Log something in systemverilog so we know it happens in simulation.
      // For now, we have the "reset" button to get us out of this situation.
    end // S_BUSYWAIT
    
    S_DONE: begin
      // We're done. :)
      // Stay in this state forever... or until rst.
      // TODO: Maybe go into another lower power state with
      // no FF assigments??
      active <= 0;
      done <= 1;
      i2c_activate <= 0; // Just in case
    end
    
    default: begin
      // This should never happen - log something in simulation
      $display("Default case in adv7513_setup state - should never happen.");
      setup_state <= S_RESET;
    end // default
  
  endcase // setup_state

end // always_ff for state machine

endmodule // adv7513_setup




`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// Restore the default_nettype to prevent side effects
// See: https://front-end-verification.blogspot.com/2010/10/implicit-net-declartions-in-verilog-and.html
// and: https://sutherland-hdl.com/papers/2006-SNUG-Boston_standard_gotchas_presentation.pdf
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
