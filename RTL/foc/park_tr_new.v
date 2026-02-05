//--------------------------------------------------------------------------------------------------------
// 模块： park_tr
// Type    : synthesizable
// Standard: Verilog 2001 (IEEE1364-2001)
// 功能： park 变换器 (Optimized to use only 2 multipliers, with proper latching)
//--------------------------------------------------------------------------------------------------------

module park_tr(
    input  wire               rstn,
    input  wire               clk,
    input  wire        [11:0] psi,
    input  wire               i_en,
    input  wire signed [15:0] i_ialpha, i_ibeta,
    output reg                o_en,
    output reg  signed [15:0] o_id, o_iq
);

wire signed [15:0] sin_psi, cos_psi;  // -1~+1 is mapped to -16384~+16384

reg               en_s1, en_s2, en_s3;
reg signed [15:0] lat_ialpha, lat_ibeta;
reg signed [15:0] lat_sin, lat_cos;
reg signed [31:0] alpha_cos, beta_sin;  // Latched Stage 1 products (for o_id)
reg signed [31:0] alpha_sin, beta_cos;  // Latched Stage 2 products (for o_iq)

// Shared multipliers (only 2)
reg signed [15:0] mul1_a, mul1_b;  // Inputs for multiplier 1
reg signed [15:0] mul2_a, mul2_b;  // Inputs for multiplier 2
reg signed [31:0] mul1_res, mul2_res;  // Results

wire signed [31:0] ide = alpha_cos + beta_sin;
wire signed [31:0] iqe = beta_cos - alpha_sin;

always @(posedge clk) begin
    mul1_res <= mul1_a * mul1_b;
    mul2_res <= mul2_a * mul2_b;
end

sincos u_sincos (
    .rstn        ( rstn       ),
    .clk         ( clk        ),
    .i_en        ( i_en       ),  // Now triggered by i_en to align validity
    .i_theta     ( psi        ),
    .o_en        (            ),  // Ignore o_en for simplicity (assume consistent latency)
    .o_sin       ( sin_psi    ),
    .o_cos       ( cos_psi    )
);

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {en_s1, en_s2, en_s3} <= 0;
        {lat_ialpha, lat_ibeta, lat_sin, lat_cos} <= 0;
        {alpha_cos, beta_sin, alpha_sin, beta_cos} <= 0;
        {mul1_a, mul1_b, mul2_a, mul2_b} <= 0;
    end else begin
        en_s1 <= i_en;
        en_s2 <= en_s1;
        en_s3 <= en_s2;

        if (i_en) begin
            lat_ialpha <= i_ialpha;
            lat_ibeta <= i_ibeta;
            // Latch sin/cos one cycle later to mimic original timing
        end

        if (en_s1) begin
            lat_sin <= sin_psi;
            lat_cos <= cos_psi;

            alpha_cos <= mul1_res;
            beta_sin <= mul2_res;

            mul1_a <= lat_ialpha;
            mul1_b <= lat_sin;

            mul2_a <= lat_ibeta;
            mul2_b <= lat_cos;
        end

        if (en_s2) begin
            alpha_sin <= mul1_res;
            beta_cos <= mul2_res;
        end

        mul1_a <= i_ialpha;
        mul1_b <= cos_psi;

        mul2_a <= i_ibeta;
        mul2_b <= sin_psi;
    end

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {o_en, o_id, o_iq} <= 0;
    end else begin
        o_en <= en_s3;
        if(en_s3) begin
            o_id <= ide[31:16];
            o_iq <= iqe[31:16];
        end
    end

endmodule
