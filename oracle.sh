#!/bin/bash
os=oracle

>${os}.log

if (( $# > 0 )); then
    images=("$@")
else
    images=(
        ol-8.10
        ol-9.8
        ol-10.3
    )
fi

for img in "${images[@]}"; do
   imgid=$(grep -i id: samples/images/${os}/${img}.yml | awk '{ print $2 }' | cut -d. -f1)
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
