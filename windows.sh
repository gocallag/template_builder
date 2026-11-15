#!/bin/bash
os=windows

>${os}.log

for img in windows-2019 windows-2022 windows-2025; do
   imgid=$(grep -i id: samples/images/${os}/${img}.yml | awk '{ print $2 }')
   imgsize=$(./ib artifact ${imgid} | grep -i base | awk '{ print $3 }')
   echo $imgsize
   if [ "$imgsize" == "" ]; then
      ./ib phase base samples/images/${os}/${img} --follow | tee -a ubuntu.log
   fi
   ./ib phase patch samples/images/${os}/${img} --follow | tee -a ubuntu.log
   ./ib build samples/images/${os}/${img} --follow | tee -a ubuntu.log
   ./ib phase clean samples/images/${os}/${img} --follow
done