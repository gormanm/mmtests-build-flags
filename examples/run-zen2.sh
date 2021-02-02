#!/bin/bash

VERSION="zen2-v1r1"
MMTESTS_GIT_COMMIT="24a792e4767222b6657fadf838772565894abfa4"
MONITORS="no-monitor"
LOCAL_MIRROR=UNAVAILABLE
export MMTESTS_TOOLCHAIN="gcc-10"

# build-flags control
export BUILDFLAGS_ENABLE_COMPILEFLAGS=yes
export BUILDFLAGS_ENABLE_MPIFLAGS=no
export BUILDFLAGS_ENABLE_SYSCTL=no

rm -f /tmp/restore.sysctl
echo Backing up sysctl
for SYSCTL in kernel.numa_balancing; do
	sudo sysctl $SYSCTL | sed -e 's/ = /=/' | tee -a /tmp/restore.sysctl
done

CONFIG_LIST="
config-workload-stream-single-zen2
config-workload-stream-omp-llcs-spread-zen2
config-workload-stream-omp-llcs-zen2
config-workload-stream-omp-nodes-spread-zen2
config-workload-stream-omp-nodes-zen2
"

if [ ! -e run-mmtests.sh ]; then
	echo Does not appear to be a mmtests installation
	exit -1
fi

restore_sysctl() {
	for SYSCTL in `cat /tmp/restore.sysctl`; do
		sudo sysctl $SYSCTL
	done
}
cleanup() {
	git checkout config
	git checkout shellpacks/common-config.sh
	restore_sysctl
}
trap cleanup EXIT

# Update mmtests and bring is to a known state
git remote update || exit -1
git checkout origin/master || exit -1
if [ "$MMTESTS_GIT_COMMIT" != "" ]; then
	if [ "$MMTESTS_GIT_COMMIT" != `git rev-parse origin/master` ]; then
		echo WARNING: MMTests commit does not match origin/master
		echo This may not be an issue but double check if it is intended.
		echo Optionally clear the MMTESTS_GIT_COMMIT at the start of
		echo the script
		sleep 5
		git checkout $MMTESTS_GIT_COMMIT || exit -1
	fi
fi
sed -i -e "s/mcp/$LOCAL_MIRROR/" shellpacks/common-config.sh
git clean -f configs &> /dev/null
./bin/autogen-configs

# Update build-flags
./bin/update-build-flags.sh

umount work/testdisk 2> /dev/null
rm -rf work/testdisk
rm -rf work/tmp

for MONITOR in $MONITORS; do
	LOGNAME=
	if [ "$MONITOR" = "run-monitor" ]; then
		LOGNAME="-monitor"
	fi

	for CONFIG in $CONFIG_LIST; do
		TESTNAME=`echo $CONFIG | sed -e 's/config-workload-stream-//' -e 's/-zen.*//'`
		if [ -e /tmp/STOP ]; then
			echo Stopping
			rm /tmp/STOP
			exit
		fi
		if [ -e work/log/$TESTNAME ]; then
			echo Skipping $CONFIG
			continue
		fi
		rm shellpacks/shellpack-*

		umount work/testdisk 2> /dev/null

		SAVE_TOOLCHAIN=$MMTESTS_TOOLCHAIN
		cp configs/$CONFIG config
		if [ $? -ne 0 ]; then
			echo Failed to copy configs/$CONFIG
			exit -1
		fi

		echo Executing run-all $MONITOR $MMTESTS_TOOLCHAIN $CONFIG
		mkdir -p work/log
		./run-mmtests.sh --$MONITOR $TESTNAME 2>&1 | tee work/log/$CONFIG.log
		echo $? > work/log/$CONFIG.status
		export MMTESTS_TOOLCHAIN=$SAVE_TOOLCHAIN
		restore_sysctl
	done
done