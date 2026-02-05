module cartesian2polar #(
    parameter ATTENUAION = 0  // Optional right-shift for rho attenuation (e.g., for SVPWM scaling)
) (
    input wire clk,
    input wire rstn,
    input wire i_en,
    input wire signed [15:0] i_x,
    input wire signed [15:0] i_y,
    output reg [11:0] o_rho,
    output reg [11:0] o_theta,
    output reg o_en
);

    // Internal registers for CORDIC computation (20-bit signed for overflow prevention)
    reg signed [19:0] X, Y, Z;
    reg [3:0] cnt;  // Counter for iterations (13: setup, 12 to 1: iterations)
    reg [1:0] quadrant;  // {y_neg, x_neg}
    reg swap;  // Whether to swap x and y for >45° in quadrant
    reg [4:0] shift_amt;  // Normalization shift amount (up to 18)

    // Temporary variables (declared at module level for Verilog compatibility)
    reg [15:0] abs_x;
    reg [15:0] abs_y;
    reg [15:0] max_abs;
    reg [4:0] msb_pos;
    reg [35:0] shifted_x;
    reg [35:0] shifted_y;
    reg [35:0] mul_x;
    reg [35:0] mul_y;
    reg [3:0] iter;
    reg signed [19:0] shift_x;
    reg signed [19:0] shift_y;
    reg signed [12:0] atan_val;
    reg [19:0] descaled_rho;
    reg [19:0] attenuated_rho;
    reg [12:0] base_theta;
    reg [12:0] temp_theta;

    // Atan lookup table (13-bit for safety, scaled where 4096 = 360°)
    // These are approximate atan(2^-i) * (4096 / (2*pi / (pi/180))) but adjusted for degrees: 4096 units = 360°
    wire [12:0] atan_table [0:11];
    assign atan_table[0]  = 13'd512;  // atan(1)    ≈ 45°
    assign atan_table[1]  = 13'd303;  // atan(0.5)  ≈ 26.565°
    assign atan_table[2]  = 13'd160;  // atan(0.25) ≈ 14.036°
    assign atan_table[3]  = 13'd81;   // atan(0.125)≈ 7.125°
    assign atan_table[4]  = 13'd41;   // atan(0.0625)≈ 3.576°
    assign atan_table[5]  = 13'd20;   // atan(0.03125)≈ 1.790°
    assign atan_table[6]  = 13'd10;   // atan(0.015625)≈ 0.895°
    assign atan_table[7]  = 13'd5;    // atan(0.0078125)≈ 0.448°
    assign atan_table[8]  = 13'd3;    // atan(0.00390625)≈ 0.224°
    assign atan_table[9]  = 13'd1;    // atan(0.001953125)≈ 0.112°
    assign atan_table[10] = 13'd1;    // atan(0.0009765625)≈ 0.056°
    assign atan_table[11] = 13'd0;    // atan(0.00048828125)≈ 0.028° (rounded to 0 for precision)

    // CORDIC gain inverse (K ≈1.64676, K_INV ≈0.60725 * 2^15 ≈19898)
    localparam [15:0] K_INV = 16'd19898;

    // Function to compute floor_log2 (position of highest set bit)
    function [4:0] floor_log2;
        input [15:0] val;
        integer i;
        begin
            floor_log2 = 0;
            for (i = 15; i >= 0; i = i - 1) begin
                if (val[i]) begin
                    floor_log2 = i;
                    i = -1;  // Break loop
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            X <= 0;
            Y <= 0;
            Z <= 0;
            cnt <= 0;
            quadrant <= 0;
            swap <= 0;
            shift_amt <= 0;
            o_rho <= 0;
            o_theta <= 0;
            o_en <= 0;
            abs_x <= 0;
            abs_y <= 0;
            max_abs <= 0;
            msb_pos <= 0;
            shifted_x <= 0;
            shifted_y <= 0;
            mul_x <= 0;
            mul_y <= 0;
            iter <= 0;
            shift_x <= 0;
            shift_y <= 0;
            atan_val <= 0;
            descaled_rho <= 0;
            attenuated_rho <= 0;
            base_theta <= 0;
            temp_theta <= 0;
        end else begin
            if (i_en && cnt == 0) begin
                // Step 1: Input processing
                if (i_x == 0 && i_y == 0) begin
                    // Zero vector special case
                    o_rho <= 0;
                    o_theta <= 0;
                    o_en <= 1;
                end else begin
                    // Compute absolute values (unsigned)
                    abs_x = i_x[15] ? (~i_x + 16'd1) : i_x;  // Two's complement negation if negative
                    abs_y = i_y[15] ? (~i_y + 16'd1) : i_y;
                    
                    quadrant <= {i_y[15], i_x[15]};  // {y_neg, x_neg}
                    swap <= (abs_x < abs_y);
                    
                    // Normalization: Find max abs and compute shift_amt to scale to ~2^18
                    max_abs = (abs_x > abs_y) ? abs_x : abs_y;
                    msb_pos = (max_abs == 0) ? 0 : floor_log2(max_abs);
                    shift_amt <= 5'd18 - msb_pos;  // Scale up to use full precision
                    
                    // Initialize for setup cycle
                    cnt <= 4'd13;  // Setup cycle
                    o_en <= 0;
                    
                    // Temporarily store abs_x and abs_y for setup
                    X <= {4'd0, abs_x};  // Temp storage in X/Y (will be overwritten in setup)
                    Y <= {4'd0, abs_y};
                end
            end else if (cnt == 13) begin
                // Step 2: Setup cycle - Scale and apply gain correction
                abs_x = X[15:0];
                abs_y = Y[15:0];
                
                // Shift as unsigned (use wider intermediate to avoid overflow)
                shifted_x = {20'd0, swap ? abs_y : abs_x} << shift_amt;
                shifted_y = {20'd0, swap ? abs_x : abs_y} << shift_amt;
                
                // Apply K_INV (unsigned multiply, then >>15)
                mul_x = (shifted_x[19:0] * K_INV) >> 15;  // Truncate to fit
                mul_y = (shifted_y[19:0] * K_INV) >> 15;
                
                // Initialize CORDIC registers (positive, signed 20-bit)
                X <= mul_x[19:0];
                Y <= mul_y[19:0];
                Z <= 0;
                
                cnt <= 4'd12;  // Start iterations
            end else if (cnt > 1) begin
                // Step 3: CORDIC vectoring iterations
                iter = 4'd12 - cnt;  // iter from 0 to 11
                shift_x = X >>> iter;  // Arithmetic right shift
                shift_y = Y >>> iter;
                atan_val = atan_table[iter];
                
                if (Y >= 0) begin
                    // Rotate clockwise
                    X <= X + shift_y;
                    Y <= Y - shift_x;
                    Z <= Z + atan_val;
                end else begin
                    // Rotate counterclockwise
                    X <= X - shift_y;
                    Y <= Y + shift_x;
                    Z <= Z - atan_val;
                end
                
                cnt <= cnt - 1;
            end else if (cnt == 1) begin
                // Step 4: Output computation
                // Rho: Descale and attenuate (X is positive after vectoring)
                descaled_rho = X >> shift_amt;  // Unsigned shift
                attenuated_rho = descaled_rho >> ATTENUAION;
                o_rho <= (attenuated_rho > 4095) ? 12'd4095 : attenuated_rho[11:0];
                
                // Theta: Compute base and adjust for quadrant/swap
                base_theta = swap ? (13'd1024 - {1'b0, Z[11:0]}) : {1'b0, Z[11:0]};
                case (quadrant)
                    2'b00: temp_theta = base_theta;             // First quadrant
                    2'b01: temp_theta = 13'd4096 - base_theta;  // Fourth quadrant
                    2'b10: temp_theta = 13'd2048 - base_theta;  // Second quadrant
                    2'b11: temp_theta = 13'd2048 + base_theta;  // Third quadrant
                endcase
                if (temp_theta >= 4096) temp_theta = temp_theta - 13'd4096;  // Wrap around
                o_theta <= temp_theta[11:0];
                
                o_en <= 1;
                cnt <= 0;  // Reset for next input
            end else begin
                o_en <= 0;
            end
        end
    end

endmodule
