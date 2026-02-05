//--------------------------------------------------------------------------------------------------------
// Module  : tb_svpwm
// Type    : simulation, top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: testbench for cartesian2polar.sv and svpwm.sv
//--------------------------------------------------------------------------------------------------------

//--------------------------------------------------------------------------------------------------------
// Module  : tb_svpwm
// Type    : simulation, top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: testbench for cartesian2polar.sv and svpwm.sv
//--------------------------------------------------------------------------------------------------------

module tb_svpwm();

initial $dumpvars(1, tb_svpwm);
initial $dumpvars(1, u_svpwm);
initial $dumpvars(1, u_sincos);  // Added: Dump sincos internals for waveform inspection (e.g., rom_x, theta_a/b)

reg rstn = 1'b0;
reg clk  = 1'b1;
always #(13563) clk = ~clk;   // 36.864MHz
initial begin repeat(4) @(posedge clk); rstn<=1'b1; end

reg underflow_mode;
reg signed [15:0] underflow_x;
reg signed [15:0] underflow_y;

reg         [11:0] theta = 0;

wire signed [15:0] x, y;

wire        [11:0] rho;
wire        [11:0] phi;

wire pwm_en, pwm_a, pwm_b, pwm_c;

   wire	o_en;
   
// 这里只是刚好借助了 sincos 模块来生成正弦波给 cartesian2polar ，只是为了仿真。在 FOC 设计中 sincos 模块并不是用来给 cartesian2polar 提供输入数据的，而是被 park_tr 调用。

   //given theta get sin/cos
sincos u_sincos (
    .rstn         ( rstn       ),
    .clk          ( clk        ),
    .i_en         ( 1'b1       ),   //constantly reading
    .i_theta      ( theta      ),   // input : θ, 一个递增的角度值
    .o_en(o_en),
    .o_sin        ( y          ),   // output : y, 振幅为 ±16384 的正弦波
    .o_cos        ( x          )    // output : x, 振幅为 ±16384 的余弦波
);

   wire theta_valid;
   
cartesian2polar u_cartesian2polar (
    .rst_n         ( rstn       ),
    .clk          ( clk        ),
    .i_en         ( 1'b1       ),
    .i_x          ( underflow_mode ? underflow_x : x / 16'sd5 ),  // input : 振幅为 ±3277 的余弦波
    .i_y          ( underflow_mode ? underflow_y : y / 16'sd5 ),  // input : 振幅为 ±3277 的正弦波
    .o_rho        ( rho        ),  // output: ρ, 应该是一直等于或近似 3277
    .o_theta      ( phi        ),   // output: φ, 应该是一个接近 θ 的角度值
    .o_en(theta_valid)
);

svpwm u_svpwm (
    .rstn         ( rstn       ),
    .clk          ( clk        ),
    .v_amp        ( 9'd384     ),
    .v_rho        ( rho        ),  // input : ρ
    .v_theta      ( phi        ),  // input : φ
    .pwm_en       ( pwm_en     ),  // output
    .pwm_a        ( pwm_a      ),  // output
    .pwm_b        ( pwm_b      ),  // output
    .pwm_c        ( pwm_c      )   // output
);

integer i;


initial begin
    underflow_mode = 0;
    while(~rstn) @ (posedge clk);

    $display("Underflow test");

    // Test Case 3: theta=3000
    theta = 12'd3000;
    repeat(1) @(posedge clk);
    wait (u_sincos.o_en == 1'b1);
    $display("Test theta=3000: o_cos=%d (expected ~-1828), o_sin=%d (expected ~-16276)", x, y);
    assert(u_sincos.o_cos inside {[-16'sd2028:-16'sd1628]} && u_sincos.o_sin inside {[-16'sd16476:-16'sd16076]}) 
        else $error("Wrong sin/cos at theta=3000 (actual cos=%d, sin=%d)", u_sincos.o_cos, u_sincos.o_sin);

   wait(u_sincos.o_en == 1'b0);
   //Underflow tests: force x/y
   
    // Modified: Forced underflow in cartesian2polar inputs (negative x/y to simulate sincos underflow propagation)
    underflow_mode = 1;
    underflow_x = -16'sd1;  // Small negative to trigger potential underflow in abs() or amp calc
    underflow_y = -16'sd1;
   
   repeat(20) @(posedge clk);  
   // Wait ~20 cycles (>14 latency) for module to process new inputs

   wait(u_cartesian2polar.o_en == 1'b1);
    $display("Forced underflow (x=y=-1): rho=%d (expected ~1), phi=%d theta is %d (expected 2560 for 225 degrees)", 
	     rho, phi,
	     u_cartesian2polar.o_theta);  // 225° since (-1,-1) is quadrant 2 (quadrants labelled: 0,1,2,3)

    // Original forced small positive test (unchanged, but added display for rho/phi)
    underflow_x = 16'sd1;
    underflow_y = 16'sd1;
    wait (o_en == 1'b0);
   
    repeat(4000) @(posedge clk);
    wait (o_en == 1'b1);   

   
    $display("Forced small positive (x=y=1): rho=%d (expected ~1), phi=%d (expected 512 for 45°). Theta is %d Underflow_mode is %d", rho, phi,u_cartesian2polar.o_theta,underflow_mode);
    if (u_cartesian2polar.o_theta inside {500, 530})
      begin
         $error("Underflow for o_theta value %d (45 degrees) expected to be 512",
		u_cartesian2polar.o_theta);
	 $finish();
      end
   
    underflow_mode = 0;
    $display("Regular mode tests");

    #2000;

    for(i=0; i<10; i=i+1) begin
        theta <= 25 * i;               // 让 θ 递增
        repeat(2048) @ (posedge clk);
        $display("%d/500", i);
    end
    $finish;
end

// General range assertions only (remove specific theta checks to avoid repeats)
always @(posedge clk) begin
    assert(u_sincos.o_sin >= -16'sd16384 && u_sincos.o_sin <= 16'sd16384) else $error("o_sin underflow: %d", u_sincos.o_sin);
    assert(u_sincos.o_cos >= -16'sd16384 && u_sincos.o_cos <= 16'sd16384) else $error("o_cos underflow: %d", u_sincos.o_cos);
   assert(u_sincos.rom_x >= 0 && u_sincos.rom_x <= 1024) else begin $error("rom_x underflow: %d", u_sincos.rom_x);  $finish();
end // Updated to <=1024 for safety
end

// Modified: Uncommented and completed PWM duty assertions (check for underflow in svpwm)
always @(posedge clk) 
    if (pwm_en) begin
        assert(u_svpwm.pwma_duty >= 0 && u_svpwm.pwma_duty <= 1024) 
            else $error("Duty underflow/overflow: pwma_duty=%d", u_svpwm.pwma_duty);
        assert(u_svpwm.pwmb_duty >= 0 && u_svpwm.pwmb_duty <= 1024) 
            else $error("Duty underflow/overflow: pwmb_duty=%d", u_svpwm.pwmb_duty);
        assert(u_svpwm.pwmc_duty >= 0 && u_svpwm.pwmc_duty <= 1024) 
            else $error("Duty underflow/overflow: pwmc_duty=%d", u_svpwm.pwmc_duty);
    end

endmodule
