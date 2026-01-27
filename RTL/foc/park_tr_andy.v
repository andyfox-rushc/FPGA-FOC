
//--------------------------------------------------------------------------------------------------------
// park_tr
// Type    : synthesizable
// Standard: Verilog 2001 (IEEE1364-2001)
// Park transform repipelined.
// The trick is note that the sincos module
// only produces a new output every 5 ticks.
// So we can pipeline the multiplication.
//
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
reg signed [15:0] sin_psi_q, cos_psi_q;

   reg signed [31:0] alpha_cos, alpha_sin, beta_cos, beta_sin;
   wire signed [31:0] ide = alpha_cos + beta_sin;
   wire signed [31:0] iqe = beta_cos  - alpha_sin;

   
   //The mutiplier machine
   wire		  sincos_valid_int;
   reg [2:0]	  mul_machine_state_q;
   localparam	  MUL_IDLE_STATE=3'b001;
   localparam	  MUL_MUL1_STATE=3'b010;
   localparam	  MUL_MUL2_STATE=3'b100;   

   //The output result machine
   reg [1:0]	  op_machine_state_q;
   localparam	  OP_IDLE_STATE=2'b01;
   localparam	  OP_COMMIT_STATE=2'b10;
   
//Note: sincos only produces 1 set of outputs every
//5 cycles. This leaves us plenty to time to 
//compute the next result. We sort of have to keep the
//the last result computed and output that very time
//we get a new value from sincos   

sincos u_sincos (
    .rstn        ( rstn       ),
    .clk         ( clk        ),
    .i_en        ( 1'b1       ), //keep on read sincos
    .i_theta     ( psi        ),
		 //this is pulsed every 5 ticks
		 //we use it to signal start multiplication
    .o_en        ( sincos_valid_int), 
    .o_sin       ( sin_psi    ),
    .o_cos       ( cos_psi    )
);


//The multipliers (only 2, we pipeline the multiplication
//to save time and energy).
   
reg do_mult_q; //power saving. Only multiply when we have to.
reg signed [15:0] mul1_a, mul1_b;  // Inputs for multiplier 1
reg signed [15:0] mul2_a, mul2_b;  // Inputs for multiplier 2
reg signed [31:0] mul1_res, mul2_res;  // Results from both

   reg		  en_s1; //for debug;
   
always @(posedge clk or negedge rstn) begin
   if (~rstn)
     begin
	mul1_res = 32'b0;
	mul2_res = 32'b0;	
     end
   else
     begin
	//Gate with do_mult_q.
	// only do the multiplication for two cycles out
	//of 5. Power saving.
	if (do_mult_q)
	  begin
	     mul1_res <= mul1_a * mul1_b;
	     mul2_res <= mul2_a * mul2_b;
	  end
     end // else: !if(~rstn)
end // always @ (posedge clk or negedge rstn)
   

//Get the data for the multiplication   
   
always @(posedge clk or negedge rstn)
  begin
     if (~rstn)
       begin
	  mul_machine_state_q <= MUL_IDLE_STATE;
	  do_mult_q <= 1'b0;
	  mul1_a <= 15'b0;
	  mul1_b <= 15'b0;
	  mul2_a <= 15'b0;
  	  mul2_b <= 15'b0;
	  cos_psi_q <= 16'b0;
	  sin_psi_q <= 16'b0;
	  alpha_cos <= 32'b0;
	  alpha_sin <= 32'b0;
	  beta_cos <= 32'b0;
	  beta_sin <= 32'b0;
	  
       end
     else
       begin
	  do_mult_q <= 1'b0; //default: turn off multipliers.
	  case (mul_machine_state_q)
	    MUL_IDLE_STATE:
	    begin
	       if (sincos_valid_int) //Bug in original code, keeps on reading memory, even if not ready !
		 begin
		    //first multiply
		    mul_machine_state_q <= MUL_MUL1_STATE;
	            mul1_a <= i_ialpha;
		    mul1_b <= cos_psi;
	            mul2_a <= i_ialpha;
		    mul2_b <= sin_psi;
		    do_mult_q <= 1'b1; //turn on multiplier
		    cos_psi_q <= cos_psi;
		    sin_psi_q <= sin_psi;
		 end
	    end
	    MUL_MUL1_STATE:
	      begin
		 //second mult
		 mul_machine_state_q <= MUL_MUL2_STATE;
		 do_mult_q <= 1'b1; //turn on multiplier
		 alpha_cos <= mul1_res;
		 alpha_sin <= mul2_res;
		 mul1_a <= i_ibeta;
		 mul1_b <= cos_psi_q;
		 mul2_a <= i_ibeta;
		 mul2_b <= sin_psi_q;
	      end // case: MUL_MUL1_STATE
	    MUL_MUL2_STATE:
	      begin
		 //results now valid, turn off multiplier.
		 mul_machine_state_q <= MUL_IDLE_STATE;
		 do_mult_q <= 1'b0; //turn off the multipliers
		 beta_cos <= mul1_res;
		 beta_sin <= mul2_res;
	      end
	    
	  endcase // case (mul_machine_state_q)
       end // else: !if(~rstn)
  end // always @ (posedge clk or negedge rstn)

//Parallel machine to update the outputs.

   
always @(posedge clk or negedge rstn)
  if (~rstn)
    begin
       op_machine_state_q <= OP_IDLE_STATE;
       o_id <= 16'b0;
       o_iq <= 16'b0;       
    end
  else
    begin
       o_en <= 1'b0;
       en_s1 <= 1'b0;
       
       case (op_machine_state_q)
	 OP_IDLE_STATE:
	   begin
	      en_s1 <= i_en; //for debug only
	      if (i_en)
		begin
		   op_machine_state_q <= OP_COMMIT_STATE;
		end
	      
	   end
	 OP_COMMIT_STATE:
	   begin
	      op_machine_state_q <= OP_IDLE_STATE;
	      o_id <= ide[31:16];
	      o_iq <= iqe[31:16];
	      o_en <= 1'b1;
	   end
       endcase // case (op_machine_state_q)
    end // else: !if(~rstn)
endmodule // park_tr




   
//original code
/*   
always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {en_s1, alpha_cos, alpha_sin, beta_cos, beta_sin} <= 0;
    end else begin
        en_s1 <= i_en;
        alpha_cos <= i_ialpha * cos_psi;
        alpha_sin <= i_ialpha * sin_psi;
        beta_cos  <= i_ibeta  * cos_psi;
        beta_sin  <= i_ibeta  * sin_psi;
    end

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {o_en, o_id, o_iq} <= 0;
    end else begin
        o_en <= en_s1;
        if(en_s1) begin
            o_id <= ide[31:16];
            o_iq <= iqe[31:16];
        end
    end
*/

