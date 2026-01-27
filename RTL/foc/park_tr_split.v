
//--------------------------------------------------------------------------------------------------------
// 模块： park_tr
// Type    : synthesizable
// Standard: Verilog 2001 (IEEE1364-2001)
// Split the multiplies over two cycles
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

reg               en_s1;
reg signed [31:0] alpha_cos, alpha_sin, beta_cos, beta_sin;
reg signed [31:0] beta_cos_d, beta_sin_d;
   //
   //Note that we use _d values (ie current values) for beta.
   //alpha_ values computed on prior state
   //
   
wire signed[31:0] ide = alpha_cos + beta_sin_d;
wire signed[31:0] iqe = beta_cos_d  - alpha_sin;

reg signed [15:0] i_ibeta_q;
reg signed [15:0] sin_psi_q, cos_psi_q;

   
sincos u_sincos (
    .rstn        ( rstn       ),
    .clk         ( clk        ),
    .i_en        ( 1'b1       ),
    .i_theta     ( psi        ),
    .o_en        (            ),
    .o_sin       ( sin_psi    ),
    .o_cos       ( cos_psi    )
);

   
//The multipliers
   wire signed [15:0] mul1_a, mul1_b, mul2_a, mul2_b;
   reg signed [31:0] mul1_res, mul2_res;

   //combinational block
   //note mul1_res and mul2_res are of type reg
   //for sequential assign
   always @(*)
     begin
	mul1_res = mul1_a * mul1_b;
	mul2_res = mul2_a * mul2_b;
     end

   //set up the arguments for the multiplier based on state.
   assign mul1_a = (en_s1) ? i_ibeta_q: i_ialpha;
   assign mul1_b = (en_s1) ? cos_psi_q: cos_psi;
   assign mul2_a = (en_s1) ? i_ibeta_q: i_ialpha;
   assign mul2_b = (en_s1) ? sin_psi_q: sin_psi;
   
   
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {alpha_cos, alpha_sin, i_ibeta_q,sin_psi_q, cos_psi_q} <= 0;
    end else begin
       if (i_en)
	 begin
	    //multiply on state when i_en asserted
            alpha_cos <= mul1_res;
            alpha_sin <= mul2_res;
	    //stash stuff for beta computation which is done on next
	    //state
	    sin_psi_q <= sin_psi;
	    cos_psi_q <= cos_psi;
	    i_ibeta_q <= i_ibeta;
	 end
    end

   //combinational logic
   //always executed on en_s1 state
   //
always @(*)
  begin
     if (en_s1) //multiply on en_s1 state (which is state after i_en)
       begin
	  beta_cos_d = mul1_res;
	  beta_sin_d = mul2_res;
       end
end
   

//Set up the state variable en_s1 to denote state 1.
//It is set once we see i_en then cleared.

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {o_en, o_id, o_iq,en_s1} <= 0;
    end else begin
       en_s1 <= i_en;
       o_en <= en_s1;
       if(en_s1) begin
          o_id <= ide[31:16];
          o_iq <= iqe[31:16];
	  en_s1 <= 1'b0;
       end
    end

endmodule
