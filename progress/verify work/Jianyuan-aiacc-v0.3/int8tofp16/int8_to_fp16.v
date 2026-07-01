module int8_to_fp16 (
    input  wire [7:0]  int8_in,
    input  wire        signed_mode,
    output wire [15:0] fp16_out
);

    wire        sign_bit;
    wire [7:0]  abs_value;
    wire [3:0]  leading_zeros;
    wire [4:0]  exponent;
    wire [9:0]  mantissa;
    wire [7:0]  normalized_value;
    
    assign sign_bit = signed_mode ? int8_in[7] : 1'b0;
    assign abs_value = sign_bit ? (~int8_in + 8'b1) : int8_in;
    
    wire is_zero;
    assign is_zero = (abs_value == 8'd0);
    
    assign leading_zeros = (abs_value[7] == 1'b1) ? 4'd0 :
                           (abs_value[6] == 1'b1) ? 4'd1 :
                           (abs_value[5] == 1'b1) ? 4'd2 :
                           (abs_value[4] == 1'b1) ? 4'd3 :
                           (abs_value[3] == 1'b1) ? 4'd4 :
                           (abs_value[2] == 1'b1) ? 4'd5 :
                           (abs_value[1] == 1'b1) ? 4'd6 :
                           (abs_value[0] == 1'b1) ? 4'd7 : 4'd8;
    
    assign normalized_value = abs_value << leading_zeros;
    
    // IEEE 754 FP16: bias = 15
    // For INT8 value v: actual_exponent = 7 - leading_zeros
    // stored_exponent = actual_exponent + 15 = (7 - leading_zeros) + 15 = 22 - leading_zeros
    assign exponent = is_zero ? 5'd0 : (5'd22 - leading_zeros);
    
    assign mantissa = is_zero ? 10'd0 : {normalized_value[6:0], 3'b0};
    
    assign fp16_out = is_zero ? {sign_bit, 5'd0, 10'd0} :
                      {sign_bit, exponent, mantissa};

endmodule