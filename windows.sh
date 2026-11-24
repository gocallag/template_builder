#!/bin/bash
os=windows

>${os}.log

if (( $# > 0 )); then
    images=("$@")
else
    images=(
        windows-2019
        windows-2022
        windows-2025
    )
fi

for img in "${images[@]}"; do
   imgid=$(grep -i id: samples/images/${os}/${img}.yml | head -n 1| awk '{ print $2 }' | cut -d. -f1)
   imgsize=$(./ib artifact ${imgid} | grep -i base | awk '{ print $3 }')
   echo $imgsize
   if [ "$imgsize" == "" ]; then
      ./ib phase base samples/images/${os}/${img} --follow | tee -a ubuntu.log
   fi
   ./ib phase patch samples/images/${os}/${img} --follow | tee -a ubuntu.log
   ./ib phase harden samples/images/${os}/${img} --follow | tee -a ubuntu.log
   ./ib build samples/images/${os}/${img} --follow | tee -a ubuntu.log
   ./ib phase clean samples/images/${os}/${img} --follow
   ./ib ps | grep STOPPED | awk '{ print $1 }' | while read ans; do echo $ans; ./ib rm $ans; done
done
