#!/bin/bash
>fedora.log

#./ib phase base samples/images/fedora/fedora-43 --follow | tee -a fedora.log
./ib phase patch samples/images/fedora/fedora-43 --follow | tee -a fedora.log
./ib build samples/images/fedora/fedora-43 --follow | tee -a fedora.log
./ib phase clean samples/images/fedora/fedora-43 --follow

#./ib phase base samples/images/fedora/fedora-44 --follow | tee -a fedora.log
./ib phase patch samples/images/fedora/fedora-44 --follow | tee -a fedora.log
./ib build samples/images/fedora/fedora-44 --follow | tee -a fedora.log
./ib phase clean samples/images/fedora/fedora-44 --follow

#./ib phase base samples/images/fedora/fedora-45 --follow | tee -a fedora.log
./ib phase patch samples/images/fedora/fedora-45 --follow | tee -a fedora.log
./ib build samples/images/fedora/fedora-45 --follow | tee -a fedora.log
./ib phase clean samples/images/fedora/fedora-45 --follow
