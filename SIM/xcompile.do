echo "Removing old snapshot and sim dir"
rm -f snapshot*
\rm -rf xsim.dir
echo "Removed"
xvlog -sv tb_svpwm_new.v  ../RTL/foc/sincos.v  ../RTL/foc/cartesian2polar.v  ../RTL/foc/svpwm.v
xelab -debug typical tb_svpwm -s snapshot
echo "Compiled"