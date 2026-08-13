Move simics_dev.sh update_simics_kernel.sh to kernel repo.

chmod +x simics_dev.sh update_simics_kernel.sh

Update SIMICS_HOST ip address in update_simics_kernel.sh

ssh-keygen -R <SIMICS_HOST>
ssh-copy-id root@<SIMICS_HOST>
