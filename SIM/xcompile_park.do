echo "Removing old snapshot and sim dir"
rm -f snapshot*
\rm -rf xsim.dir
echo "Removed"
xvlog -sv tb_clark_park_tr.v  ../RTL/foc/sincos.v  ../RTL/foc/clark_tr.v  ../RTL/foc/park_tr.v
xelab -debug typical tb_clark_park_tr -s snapshot
echo "Compiled"