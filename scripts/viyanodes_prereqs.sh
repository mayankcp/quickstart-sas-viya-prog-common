#!/bin/bash -e

# Run this script as root or sudo
# Set the following environment variables:
#   INSTALL_USER (the userid used for viya ansible install)
#   NFS_SERVER (the ip or dns of the bastion host )
#   HOST (the label/alias for the machine - services|controller)

BASTION_NFS_SHARE="/sas/install/setup"
NFS_MOUNT_POINT="/mnt/ansiblecontroller"
ANSIBLE_KEY="${NFS_MOUNT_POINT}/ansible_key/id_rsa.pub"
INSTALL_USER=${INSTALL_USER:-}
NFS_SERVER=${NFS_SERVER:-ansible}
READINESS_FLAG_FILE="${NFS_MOUNT_POINT}/readiness_flags/${HOST}"

#
# create mount dir
#
mkdir -p ${NFS_MOUNT_POINT}

#
# install and start nfs
#
yum install -y nfs-utils
systemctl start nfs
systemctl enable nfs

#
# mount nfs share
#
MOUNT="${NFS_SERVER}:${BASTION_NFS_SHARE}  ${NFS_MOUNT_POINT} nfs rw,hard,intr,bg 0 0"
grep -q "$MOUNT" /etc/fstab || echo "$MOUNT" >> /etc/fstab


mount "${NFS_MOUNT_POINT}"
RET=$?

#
# the ansible controller should already be available and fully initialized at this point
# since we need its ip address or fqdn, but the following should address
# any asynchronous scenarios
#
while [ "$RET" -gt "0" ]; do
	echo "Waiting 5 seconds for mount to be possible"
	sleep 5
	mount "${NFS_MOUNT_POINT}"
	RET=$?
done
echo "Mounting Successful"

#
# again, this may be needed if the ansible controller and the viya vms initialize in parallel
#
wait_count=0
stop_waiting_count=600
while [ ! -e "$ANSIBLE_KEY" ]; do
	echo "waiting 5 seconds for key to come around"
	sleep 1
	if [ "$((wait_count++))" -gt "$stop_waiting_count" ]; then
		exit 1
	fi
done


#
# copy public ansible key from NFS share
#
su - ${INSTALL_USER} <<END
mkdir -p ~/.ssh
cat ${ANSIBLE_KEY} >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
END

#
# post readiness flag
#
LOCALIP=$(ip -o -f inet addr | grep eth0 | sed -r 's/.*\b(([0-9]{1,3}\.){3}[0-9]{1,3})\/.*/\1/g')
echo $LOCALIP > $READINESS_FLAG_FILE


